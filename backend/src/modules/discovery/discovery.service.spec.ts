import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { DecisionType } from '@prisma/client';
import { DiscoveryService } from './discovery.service.js';

describe('DiscoveryService', () => {
  let prisma: any;
  let connections: { createSuggestion: ReturnType<typeof vi.fn>; markInterested: ReturnType<typeof vi.fn> };
  let storage: { getDownloadUrl: ReturnType<typeof vi.fn> };
  let service: DiscoveryService;

  function makeEntry(overrides: Record<string, any> = {}) {
    return {
      id: 'entry-1',
      userId: 'user-1',
      candidateId: 'candidate-1',
      queueDate: new Date('2026-09-26'),
      sequenceInDay: 0,
      decision: null,
      decidedAt: null,
      ...overrides,
    };
  }

  beforeEach(() => {
    connections = {
      createSuggestion: vi.fn(async () => ({ id: 'connection-1' })),
      markInterested: vi.fn(async () => ({ id: 'connection-1', status: 'SUGGESTED' })),
    };
    storage = { getDownloadUrl: vi.fn(async (key: string) => `https://signed.example.com/${key}`) };
    service = new DiscoveryService(prisma, connections as any, storage as any);
  });

  describe('decide', () => {
    it('throws NotFoundException when the entry does not exist', async () => {
      prisma = { discoveryQueueEntry: { findUnique: vi.fn(async () => null) } };
      service = new DiscoveryService(prisma, connections as any, storage as any);

      await expect(service.decide('user-1', 'missing', DecisionType.PASS)).rejects.toThrow(NotFoundException);
    });

    it('throws ForbiddenException when the entry belongs to a different user', async () => {
      prisma = { discoveryQueueEntry: { findUnique: vi.fn(async () => makeEntry({ userId: 'someone-else' })) } };
      service = new DiscoveryService(prisma, connections as any, storage as any);

      await expect(service.decide('user-1', 'entry-1', DecisionType.PASS)).rejects.toThrow(ForbiddenException);
    });

    it('PASS updates the entry, never touches Connections, and never reports a match', async () => {
      const entry = makeEntry();
      prisma = {
        discoveryQueueEntry: {
          findUnique: vi.fn(async () => entry),
          updateMany: vi.fn(async () => ({ count: 1 })),
        },
      };
      service = new DiscoveryService(prisma, connections as any, storage as any);

      const result = await service.decide('user-1', 'entry-1', DecisionType.PASS);

      expect(prisma.discoveryQueueEntry.updateMany).toHaveBeenCalledWith({
        where: { id: 'entry-1', decision: null },
        data: { decision: DecisionType.PASS, decidedAt: expect.any(Date) },
      });
      expect(connections.createSuggestion).not.toHaveBeenCalled();
      expect(connections.markInterested).not.toHaveBeenCalled();
      expect(result.matched).toBe(false);
    });

    it('INTERESTED updates the entry, creates + marks the Connection, and reports matched:false when only one side is interested', async () => {
      const entry = makeEntry();
      prisma = {
        discoveryQueueEntry: {
          findUnique: vi.fn(async () => entry),
          updateMany: vi.fn(async () => ({ count: 1 })),
        },
      };
      service = new DiscoveryService(prisma, connections as any, storage as any);

      const result = await service.decide('user-1', 'entry-1', DecisionType.INTERESTED);

      expect(connections.createSuggestion).toHaveBeenCalledWith('user-1', 'candidate-1');
      expect(connections.markInterested).toHaveBeenCalledWith('user-1', 'connection-1');
      expect(result.matched).toBe(false); // markInterested mock returns status SUGGESTED
    });

    it('reports matched:true when this call is the one that flips the Connection to MUTUAL_INTEREST', async () => {
      connections.markInterested = vi.fn(async () => ({ id: 'connection-1', status: 'MUTUAL_INTEREST' }));
      const entry = makeEntry();
      prisma = {
        discoveryQueueEntry: {
          findUnique: vi.fn(async () => entry),
          updateMany: vi.fn(async () => ({ count: 1 })),
        },
      };
      service = new DiscoveryService(prisma, connections as any, storage as any);

      const result = await service.decide('user-1', 'entry-1', DecisionType.INTERESTED);
      expect(result.matched).toBe(true);
    });

    it('is idempotent: a second decide() call on an already-decided entry is a no-op that returns existing state and matched:false, never re-fires side effects', async () => {
      const undecidedEntry = makeEntry();
      const decidedEntry = makeEntry({ decision: DecisionType.INTERESTED, decidedAt: new Date('2026-09-26T10:00:00Z') });

      prisma = {
        discoveryQueueEntry: {
          findUnique: vi.fn(async () => undecidedEntry),
          updateMany: vi.fn(async () => ({ count: 1 })),
        },
      };
      service = new DiscoveryService(prisma, connections as any, storage as any);
      await service.decide('user-1', 'entry-1', DecisionType.INTERESTED);
      expect(connections.createSuggestion).toHaveBeenCalledTimes(1);
      expect(connections.markInterested).toHaveBeenCalledTimes(1);

      // Second call (retry / double-tap / race loser): findUnique now
      // returns the already-decided row, and the guarded updateMany's
      // WHERE (decision: null) no longer matches -- count: 0.
      prisma.discoveryQueueEntry.findUnique = vi.fn(async () => decidedEntry);
      prisma.discoveryQueueEntry.updateMany = vi.fn(async () => ({ count: 0 }));

      const result = await service.decide('user-1', 'entry-1', DecisionType.INTERESTED);

      // No new side effects fired on the retry, and no duplicate "You
      // matched!" screen would be shown to a retrying client.
      expect(connections.createSuggestion).toHaveBeenCalledTimes(1);
      expect(connections.markInterested).toHaveBeenCalledTimes(1);
      expect(result.entry?.decision).toBe(DecisionType.INTERESTED);
      expect(result.matched).toBe(false);
    });

    it('a race between two concurrent decide() calls only lets ONE fire Connection side effects', async () => {
      // Simulate the race: both calls read the entry as undecided (they
      // interleaved before either write landed), but only the first
      // guarded updateMany can actually match `decision: null` in the DB --
      // the second one loses the race and gets count: 0.
      const entry = makeEntry();
      let updateCallCount = 0;
      prisma = {
        discoveryQueueEntry: {
          findUnique: vi.fn(async () => entry),
          updateMany: vi.fn(async () => {
            updateCallCount += 1;
            return { count: updateCallCount === 1 ? 1 : 0 };
          }),
        },
      };
      service = new DiscoveryService(prisma, connections as any, storage as any);

      await Promise.all([
        service.decide('user-1', 'entry-1', DecisionType.INTERESTED),
        service.decide('user-1', 'entry-1', DecisionType.INTERESTED),
      ]);

      expect(connections.createSuggestion).toHaveBeenCalledTimes(1);
      expect(connections.markInterested).toHaveBeenCalledTimes(1);
    });
  });

  describe('today', () => {
    it('returns [] without querying profiles/voice answers when there are no undecided entries', async () => {
      prisma = {
        discoveryQueueEntry: { findMany: vi.fn(async () => []) },
        profile: { findMany: vi.fn() },
        voiceAnswer: { findMany: vi.fn() },
      };
      service = new DiscoveryService(prisma, connections as any, storage as any);

      const result = await service.today('user-1');

      expect(result).toEqual([]);
      expect(prisma.profile.findMany).not.toHaveBeenCalled();
      expect(prisma.voiceAnswer.findMany).not.toHaveBeenCalled();
      expect(prisma.discoveryQueueEntry.findMany).toHaveBeenCalledWith({
        where: { userId: 'user-1', decision: null },
        orderBy: [{ queueDate: 'desc' }, { sequenceInDay: 'asc' }],
      });
    });

    it('joins in candidate displayName, signed photo URL, and signed voice clip URL', async () => {
      const entry = makeEntry({ id: 'entry-1', candidateId: 'candidate-1' });
      prisma = {
        discoveryQueueEntry: { findMany: vi.fn(async () => [entry]) },
        profile: {
          findMany: vi.fn(async () => [
            { userId: 'candidate-1', displayName: 'Alex', photoUrl: 'photo/abc.jpg' },
          ]),
        },
        voiceAnswer: {
          findMany: vi.fn(async () => [
            { userId: 'candidate-1', audioUrl: 'voice/xyz.webm', updatedAt: new Date('2026-09-20') },
          ]),
        },
      };
      service = new DiscoveryService(prisma, connections as any, storage as any);

      const [view] = await service.today('user-1');

      expect(view.candidate.displayName).toBe('Alex');
      expect(view.candidate.photoUrl).toBe('https://signed.example.com/photo/abc.jpg');
      expect(view.candidate.voiceClipUrl).toBe('https://signed.example.com/voice/xyz.webm');
      expect(storage.getDownloadUrl).toHaveBeenCalledWith('photo/abc.jpg');
      expect(storage.getDownloadUrl).toHaveBeenCalledWith('voice/xyz.webm');
    });

    it('tolerates a candidate with no photo and no approved voice answer -- nulls, not errors', async () => {
      const entry = makeEntry();
      prisma = {
        discoveryQueueEntry: { findMany: vi.fn(async () => [entry]) },
        profile: { findMany: vi.fn(async () => [{ userId: 'candidate-1', displayName: 'Alex', photoUrl: null }]) },
        voiceAnswer: { findMany: vi.fn(async () => []) },
      };
      service = new DiscoveryService(prisma, connections as any, storage as any);

      const [view] = await service.today('user-1');

      expect(view.candidate.photoUrl).toBeNull();
      expect(view.candidate.voiceClipUrl).toBeNull();
      expect(storage.getDownloadUrl).not.toHaveBeenCalled();
    });

    it('picks the most recently updated approved voice answer when a candidate has more than one', async () => {
      const entry = makeEntry();
      prisma = {
        discoveryQueueEntry: { findMany: vi.fn(async () => [entry]) },
        profile: { findMany: vi.fn(async () => []) },
        voiceAnswer: {
          // Simulates the query's own `orderBy: { updatedAt: 'desc' }` --
          // most recent first, so the service's "first wins" logic picks it.
          findMany: vi.fn(async () => [
            { userId: 'candidate-1', audioUrl: 'voice/newest.webm', updatedAt: new Date('2026-09-25') },
            { userId: 'candidate-1', audioUrl: 'voice/oldest.webm', updatedAt: new Date('2026-01-01') },
          ]),
        },
      };
      service = new DiscoveryService(prisma, connections as any, storage as any);

      const [view] = await service.today('user-1');
      expect(view.candidate.voiceClipUrl).toBe('https://signed.example.com/voice/newest.webm');
    });
  });
});
