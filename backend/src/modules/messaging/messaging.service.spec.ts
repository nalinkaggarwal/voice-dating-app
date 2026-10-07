import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { MessageType } from '@prisma/client';
import { MessagingService } from './messaging.service.js';

describe('MessagingService', () => {
  let service: MessagingService;
  let prisma: any;
  let storage: { generateKey: ReturnType<typeof vi.fn>; getUploadUrl: ReturnType<typeof vi.fn>; getDownloadUrl: ReturnType<typeof vi.fn> };
  let gateway: { broadcastToChat: ReturnType<typeof vi.fn> };

  function makeConnection(overrides: Record<string, any> = {}) {
    return { id: 'conn-1', userAId: 'user-a', userBId: 'user-b', status: 'ACTIVE', ...overrides };
  }

  function makeMessage(overrides: Record<string, any> = {}) {
    return {
      id: 'msg-1',
      connectionId: 'conn-1',
      senderId: 'user-a',
      type: MessageType.TEXT,
      textContent: 'hey',
      audioUrl: null,
      audioDurationSec: null,
      sentAt: new Date('2026-10-01T10:00:00Z'),
      deliveredAt: null,
      readAt: null,
      ...overrides,
    };
  }

  beforeEach(() => {
    prisma = {
      connection: {
        findUnique: vi.fn(async () => makeConnection()),
        updateMany: vi.fn(async () => ({ count: 1 })),
      },
      message: {
        create: vi.fn(async ({ data }: any) => makeMessage(data)),
        findMany: vi.fn(async () => []),
        findFirst: vi.fn(async () => null),
        updateMany: vi.fn(async () => ({ count: 1 })),
      },
      profile: { findUnique: vi.fn(async () => null) },
      block: { findFirst: vi.fn(async () => null) },
    };
    storage = {
      generateKey: vi.fn(() => 'message-voice/abc.m4a'),
      getUploadUrl: vi.fn(async () => 'https://s3.example.com/signed-put'),
      getDownloadUrl: vi.fn(async (key: string) => `https://signed.example.com/${key}`),
    };
    gateway = { broadcastToChat: vi.fn() };

    service = new MessagingService(prisma, storage as any, gateway as any);
  });

  describe('access control (every method)', () => {
    const rejectedStatuses = ['SUGGESTED', 'MUTUAL_INTEREST', 'SNAP_PENDING', 'CLOSED', 'BLOCKED'];

    it.each(rejectedStatuses)('sendMessage rejects status %s', async (status) => {
      prisma.connection.findUnique = vi.fn(async () => makeConnection({ status }));
      await expect(
        service.sendMessage('user-a', 'conn-1', { type: MessageType.TEXT, textContent: 'hi' } as any),
      ).rejects.toThrow(ForbiddenException);
    });

    it.each(rejectedStatuses)('getHistory rejects status %s', async (status) => {
      prisma.connection.findUnique = vi.fn(async () => makeConnection({ status }));
      await expect(service.getHistory('user-a', 'conn-1', {})).rejects.toThrow(ForbiddenException);
    });

    it.each(['AUTHENTICATED_MATCH', 'ACTIVE'])('sendMessage allows status %s', async (status) => {
      prisma.connection.findUnique = vi.fn(async () => makeConnection({ status }));
      await expect(
        service.sendMessage('user-a', 'conn-1', { type: MessageType.TEXT, textContent: 'hi' } as any),
      ).resolves.toBeDefined();
    });

    it('throws NotFoundException for a nonexistent connection', async () => {
      prisma.connection.findUnique = vi.fn(async () => null);
      await expect(service.getHistory('user-a', 'nope', {})).rejects.toThrow(NotFoundException);
    });

    it.each(['user-a', 'user-b'])(
      'rejects send/fetch for %s when the pair is blocked, even though Connection.status is ACTIVE (defense in depth)',
      async (callerId) => {
        prisma.connection.findUnique = vi.fn(async () => makeConnection({ status: 'ACTIVE' }));
        prisma.block.findFirst = vi.fn(async () => ({ id: 'block-1', blockerId: 'user-b', blockedId: 'user-a' }));
        await expect(
          service.sendMessage(callerId, 'conn-1', { type: MessageType.TEXT, textContent: 'hi' } as any),
        ).rejects.toThrow(ForbiddenException);
        await expect(service.getHistory(callerId, 'conn-1', {})).rejects.toThrow(ForbiddenException);
      },
    );

    it('IDOR guardrail: throws ForbiddenException for a user not party to the connection', async () => {
      await expect(service.getHistory('someone-else', 'conn-1', {})).rejects.toThrow(ForbiddenException);
      await expect(
        service.sendMessage('someone-else', 'conn-1', { type: MessageType.TEXT, textContent: 'hi' } as any),
      ).rejects.toThrow(ForbiddenException);
    });
  });

  describe('sendMessage', () => {
    it('persists a TEXT message and broadcasts message:new', async () => {
      const result = await service.sendMessage('user-a', 'conn-1', {
        type: MessageType.TEXT,
        textContent: 'hello there',
      } as any);

      expect(prisma.message.create).toHaveBeenCalledWith({
        data: {
          connectionId: 'conn-1',
          senderId: 'user-a',
          type: MessageType.TEXT,
          textContent: 'hello there',
          audioUrl: null,
          audioDurationSec: null,
        },
      });
      expect(gateway.broadcastToChat).toHaveBeenCalledWith('conn-1', 'message:new', result);
    });

    it('persists a VOICE message with url and duration', async () => {
      await service.sendMessage('user-a', 'conn-1', {
        type: MessageType.VOICE,
        audioUrl: 'message-voice/abc.m4a',
        audioDurationSec: 12,
      } as any);

      expect(prisma.message.create).toHaveBeenCalledWith({
        data: {
          connectionId: 'conn-1',
          senderId: 'user-a',
          type: MessageType.VOICE,
          textContent: null,
          audioUrl: 'message-voice/abc.m4a',
          audioDurationSec: 12,
        },
      });
    });

    it('rejects a TEXT message with no textContent', async () => {
      await expect(
        service.sendMessage('user-a', 'conn-1', { type: MessageType.TEXT } as any),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects a VOICE message missing audioUrl', async () => {
      await expect(
        service.sendMessage('user-a', 'conn-1', { type: MessageType.VOICE, audioDurationSec: 10 } as any),
      ).rejects.toThrow(BadRequestException);
    });

    it('rejects a VOICE message over the 60s cap', async () => {
      await expect(
        service.sendMessage('user-a', 'conn-1', {
          type: MessageType.VOICE,
          audioUrl: 'x',
          audioDurationSec: 61,
        } as any),
      ).rejects.toThrow(BadRequestException);
    });

    it('transitions AUTHENTICATED_MATCH -> ACTIVE on the first message', async () => {
      prisma.connection.findUnique = vi.fn(async () => makeConnection({ status: 'AUTHENTICATED_MATCH' }));

      await service.sendMessage('user-a', 'conn-1', { type: MessageType.TEXT, textContent: 'hi' } as any);

      expect(prisma.connection.updateMany).toHaveBeenCalledWith({
        where: { id: 'conn-1', status: 'AUTHENTICATED_MATCH' },
        data: { status: 'ACTIVE' },
      });
    });

    it('does not re-attempt the status transition once already ACTIVE', async () => {
      prisma.connection.findUnique = vi.fn(async () => makeConnection({ status: 'ACTIVE' }));

      await service.sendMessage('user-a', 'conn-1', { type: MessageType.TEXT, textContent: 'hi' } as any);

      expect(prisma.connection.updateMany).not.toHaveBeenCalled();
    });
  });

  describe('getHistory', () => {
    it('paginates backward with `before`, reporting hasMore when there are older rows left', async () => {
      const rows = Array.from({ length: 31 }, (_, i) => makeMessage({ id: `msg-${i}`, sentAt: new Date(2026, 9, 1, 10, i) }));
      prisma.message.findMany = vi.fn(async () => rows); // limit+1 = 31 returned

      const result = await service.getHistory('user-a', 'conn-1', { limit: 30 });

      expect(result.hasMore).toBe(true);
      expect(result.messages).toHaveLength(30);
      // returned in chronological order despite the query being newest-first
      expect(result.messages[0].id).toBe('msg-29');
      expect(result.messages[29].id).toBe('msg-0');
    });

    it('reports hasMore:false when there are no more rows than the page size', async () => {
      prisma.message.findMany = vi.fn(async () => [makeMessage()]);
      const result = await service.getHistory('user-a', 'conn-1', { limit: 30 });
      expect(result.hasMore).toBe(false);
      expect(result.messages).toHaveLength(1);
    });

    it('caps an oversized limit request at MAX_PAGE_SIZE', async () => {
      await service.getHistory('user-a', 'conn-1', { limit: 99999 });
      expect(prisma.message.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ take: 101 }), // MAX_PAGE_SIZE (100) + 1
      );
    });

    it('reconnect catch-up: `since` fetches everything newer, ascending, no pagination', async () => {
      const rows = [makeMessage({ id: 'msg-2' })];
      prisma.message.findMany = vi.fn(async () => rows);

      const result = await service.getHistory('user-a', 'conn-1', { since: '2026-10-01T09:00:00Z' });

      expect(prisma.message.findMany).toHaveBeenCalledWith({
        where: { connectionId: 'conn-1', sentAt: { gt: new Date('2026-10-01T09:00:00Z') } },
        orderBy: { sentAt: 'asc' },
      });
      expect(result).toEqual({ messages: rows, hasMore: false });
    });
  });

  describe('markDelivered / markRead', () => {
    it('markDelivered updates only the other party\'s undelivered messages and broadcasts', async () => {
      const result = await service.markDelivered('user-a', 'conn-1');

      expect(prisma.message.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ connectionId: 'conn-1', senderId: { not: 'user-a' }, deliveredAt: null }),
        }),
      );
      expect(gateway.broadcastToChat).toHaveBeenCalledWith('conn-1', 'message:delivered', {
        connectionId: 'conn-1',
        upTo: result.upTo,
      });
    });

    it('markRead sets both deliveredAt (if unset) and readAt, then broadcasts', async () => {
      const result = await service.markRead('user-a', 'conn-1');

      expect(prisma.message.updateMany).toHaveBeenCalledTimes(2);
      expect(gateway.broadcastToChat).toHaveBeenCalledWith('conn-1', 'message:read', {
        connectionId: 'conn-1',
        upTo: result.upTo,
      });
    });
  });

  describe('listConversations', () => {
    it('returns one entry per AUTHENTICATED_MATCH/ACTIVE connection with the other party\'s profile + last message', async () => {
      prisma.connection.findMany = vi.fn(async () => [makeConnection({ id: 'conn-1', userAId: 'user-a', userBId: 'user-b' })]);
      prisma.profile.findUnique = vi.fn(async () => ({ userId: 'user-b', displayName: 'Jordan', photoUrl: 'photos/jordan.jpg' }));
      prisma.message.findFirst = vi.fn(async () => makeMessage({ textContent: 'hows it going' }));

      const result = await service.listConversations('user-a');

      expect(result).toEqual([
        {
          connectionId: 'conn-1',
          otherUserId: 'user-b',
          displayName: 'Jordan',
          photoUrl: 'https://signed.example.com/photos/jordan.jpg',
          lastMessage: { type: MessageType.TEXT, textContent: 'hows it going', sentAt: expect.any(Date) },
        },
      ]);
    });

    it('returns lastMessage:null for a match with no messages yet', async () => {
      prisma.connection.findMany = vi.fn(async () => [makeConnection()]);
      const result = await service.listConversations('user-a');
      expect(result[0].lastMessage).toBeNull();
    });
  });

  describe('requestVoiceUploadUrl', () => {
    it('generates a key and returns a signed PUT URL', async () => {
      const result = await service.requestVoiceUploadUrl('audio/mp4');
      expect(result).toEqual({ uploadUrl: 'https://s3.example.com/signed-put', key: 'message-voice/abc.m4a' });
      expect(storage.generateKey).toHaveBeenCalledWith('message-voice', 'm4a');
    });
  });
});
