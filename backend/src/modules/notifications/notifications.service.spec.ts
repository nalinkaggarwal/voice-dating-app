import { NotificationsService } from './notifications.service.js';

describe('NotificationsService', () => {
  let service: NotificationsService;
  let prisma: any;
  let push: { sendToTokens: ReturnType<typeof vi.fn> };

  beforeEach(() => {
    prisma = {
      deviceToken: {
        upsert: vi.fn(async ({ create }: any) => ({ id: 'dt-1', ...create })),
        deleteMany: vi.fn(async () => ({ count: 1 })),
        findMany: vi.fn(async () => [
          { id: 'dt-1', userId: 'user-b', token: 'token-b-phone', platform: 'ANDROID' },
          { id: 'dt-2', userId: 'user-b', token: 'token-b-tablet', platform: 'ANDROID' },
        ]),
      },
      profile: {
        findUnique: vi.fn(async ({ where: { userId } }: any) =>
          userId === 'user-a' ? { userId, displayName: 'Asha' } : null,
        ),
      },
    };
    push = {
      sendToTokens: vi.fn(async (tokens: string[]) =>
        tokens.map((token) => ({ token, ok: true, unregistered: false })),
      ),
    };
    service = new NotificationsService(prisma, push as any);
  });

  describe('registerDevice', () => {
    it('upserts on the token so the same phone moves to whichever account is logged in', async () => {
      await service.registerDevice('user-b', 'tok', 'ANDROID');
      expect(prisma.deviceToken.upsert).toHaveBeenCalledWith({
        where: { token: 'tok' },
        create: { userId: 'user-b', token: 'tok', platform: 'ANDROID' },
        update: { userId: 'user-b', platform: 'ANDROID' },
      });
    });
  });

  describe('unregisterDevice', () => {
    it('only deletes a token that belongs to the caller', async () => {
      const result = await service.unregisterDevice('user-b', 'tok');
      expect(prisma.deviceToken.deleteMany).toHaveBeenCalledWith({ where: { token: 'tok', userId: 'user-b' } });
      expect(result).toEqual({ removed: 1 });
    });
  });

  describe('notifyNewMessage', () => {
    it('sends to every device of the recipient with the sender name and a text preview', async () => {
      const summary = await service.notifyNewMessage('user-b', {
        connectionId: 'conn-1',
        senderId: 'user-a',
        type: 'TEXT',
        textContent: 'hey there',
      });
      expect(push.sendToTokens).toHaveBeenCalledWith(['token-b-phone', 'token-b-tablet'], {
        title: 'Asha',
        body: 'hey there',
        data: { type: 'NEW_MESSAGE', connectionId: 'conn-1', otherUserId: 'user-a', otherDisplayName: 'Asha' },
      });
      expect(summary).toEqual({ requested: 2, delivered: 2, failed: 0, forgotten: 0 });
    });

    it('describes a voice message instead of previewing text', async () => {
      await service.notifyNewMessage('user-b', {
        connectionId: 'conn-1',
        senderId: 'user-a',
        type: 'VOICE',
        textContent: null,
      });
      expect(push.sendToTokens.mock.calls[0][1].body).toBe('Asha sent you a voice message');
    });

    it('truncates a long preview and collapses whitespace', async () => {
      const long = `${'word '.repeat(30)}\n\nend`;
      await service.notifyNewMessage('user-b', {
        connectionId: 'conn-1',
        senderId: 'user-a',
        type: 'TEXT',
        textContent: long,
      });
      const body: string = push.sendToTokens.mock.calls[0][1].body;
      expect(body.length).toBeLessThanOrEqual(80);
      expect(body.endsWith('…')).toBe(true);
      expect(body).not.toMatch(/\n/);
    });

    it('falls back to a neutral name when the sender has no profile/displayName', async () => {
      await service.notifyNewMessage('user-a', {
        connectionId: 'conn-1',
        senderId: 'user-b', // profile.findUnique returns null for user-b
        type: 'TEXT',
        textContent: 'hi',
      });
      expect(push.sendToTokens.mock.calls[0][1].title).toBe('Your match');
    });
  });

  describe('notifyMutualMatch -- "hear before you see"', () => {
    it('never looks up a profile and carries no name in title, body or data', async () => {
      await service.notifyMutualMatch('user-b', { connectionId: 'conn-1', otherUserId: 'user-a' });
      expect(prisma.profile.findUnique).not.toHaveBeenCalled();
      const message = push.sendToTokens.mock.calls[0][1];
      expect(JSON.stringify(message)).not.toContain('Asha');
      expect(message.data).toEqual({ type: 'MUTUAL_MATCH', connectionId: 'conn-1', otherUserId: 'user-a' });
    });
  });

  describe('notifyLiveSnapInvite / notifyAuthenticatedMatch', () => {
    it('includes the caller name on a Live Snap invite (reveal is already permitted at that status)', async () => {
      await service.notifyLiveSnapInvite('user-b', { connectionId: 'conn-1', callerId: 'user-a' });
      const message = push.sendToTokens.mock.calls[0][1];
      expect(message.title).toBe('Asha wants to Live Snap');
      expect(message.data.type).toBe('LIVE_SNAP_INVITE');
      expect(message.data.otherDisplayName).toBe('Asha');
    });

    it('names the other party on an authenticated match', async () => {
      await service.notifyAuthenticatedMatch('user-b', { connectionId: 'conn-1', otherUserId: 'user-a' });
      const message = push.sendToTokens.mock.calls[0][1];
      expect(message.body).toContain('Asha');
      expect(message.data.type).toBe('AUTHENTICATED_MATCH');
    });
  });

  describe('delivery bookkeeping', () => {
    it('skips the provider entirely when the recipient has no devices', async () => {
      prisma.deviceToken.findMany = vi.fn(async () => []);
      const summary = await service.notifyMutualMatch('user-b', { connectionId: 'conn-1', otherUserId: 'user-a' });
      expect(push.sendToTokens).not.toHaveBeenCalled();
      expect(summary).toEqual({ requested: 0, delivered: 0, failed: 0, forgotten: 0 });
    });

    it('forgets tokens the provider reports as dead, and only those', async () => {
      push.sendToTokens = vi.fn(async () => [
        { token: 'token-b-phone', ok: false, unregistered: true, error: 'messaging/registration-token-not-registered' },
        { token: 'token-b-tablet', ok: false, unregistered: false, error: 'messaging/internal-error' },
      ]);
      const summary = await service.notifyMutualMatch('user-b', { connectionId: 'conn-1', otherUserId: 'user-a' });
      expect(prisma.deviceToken.deleteMany).toHaveBeenCalledWith({ where: { token: { in: ['token-b-phone'] } } });
      expect(summary).toEqual({ requested: 2, delivered: 0, failed: 2, forgotten: 1 });
    });

    it('never throws when the provider itself blows up -- the triggering action must still succeed', async () => {
      push.sendToTokens = vi.fn(async () => {
        throw new Error('FCM credentials revoked');
      });
      const summary = await service.notifyMutualMatch('user-b', { connectionId: 'conn-1', otherUserId: 'user-a' });
      expect(summary).toEqual({ requested: 2, delivered: 0, failed: 2, forgotten: 0 });
      expect(prisma.deviceToken.deleteMany).not.toHaveBeenCalled();
    });
  });
});
