import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { ConnectionsService } from './connections.service.js';

describe('ConnectionsService', () => {
  let service: ConnectionsService;
  let prisma: any;
  let storage: { getDownloadUrl: ReturnType<typeof vi.fn> };

  function makeConnection(overrides: Record<string, any> = {}) {
    return {
      id: 'conn-1',
      userAId: 'user-a',
      userBId: 'user-b',
      status: 'MUTUAL_INTEREST',
      userAInterested: true,
      userBInterested: true,
      userASnapDone: false,
      userBSnapDone: false,
      ...overrides,
    };
  }

  let nextId = 1;

  beforeEach(() => {
    storage = { getDownloadUrl: vi.fn(async (key: string) => `https://signed.example.com/${key}`) };
    nextId = 1;

    const connectionStore = new Map<string, any>();
    const blockStore = new Map<string, any>();

    function findConnectionByPair(userAId: string, userBId: string) {
      for (const conn of connectionStore.values()) {
        if (conn.userAId === userAId && conn.userBId === userBId) return conn;
      }
      return null;
    }

    prisma = {
      connection: {
        findUnique: vi.fn(async ({ where: { id } }: any) => connectionStore.get(id) ?? null),
        update: vi.fn(async ({ where: { id }, data }: any) => {
          const updated = { ...connectionStore.get(id), ...data };
          connectionStore.set(id, updated);
          return updated;
        }),
        updateMany: vi.fn(async ({ where, data }: any) => {
          const existing = connectionStore.get(where.id);
          if (!existing) return { count: 0 };
          if (where.status?.notIn?.includes(existing.status)) return { count: 0 };
          connectionStore.set(where.id, { ...existing, ...data });
          return { count: 1 };
        }),
        upsert: vi.fn(async ({ where, create, update }: any) => {
          const { userAId, userBId } = where.userAId_userBId;
          const existing = findConnectionByPair(userAId, userBId);
          if (existing) {
            const updated = { ...existing, ...update };
            connectionStore.set(existing.id, updated);
            return updated;
          }
          const created = makeConnection({ id: `conn-${nextId++}`, status: 'SUGGESTED', ...create });
          connectionStore.set(created.id, created);
          return created;
        }),
      },
      block: {
        findFirst: vi.fn(async ({ where }: any) => {
          for (const block of blockStore.values()) {
            for (const clause of where.OR) {
              if (block.blockerId === clause.blockerId && block.blockedId === clause.blockedId) return block;
            }
          }
          return null;
        }),
        upsert: vi.fn(async ({ where, create }: any) => {
          const key = `${where.blockerId_blockedId.blockerId}:${where.blockerId_blockedId.blockedId}`;
          const existing = blockStore.get(key);
          if (existing) return existing;
          const created = { id: `block-${nextId++}`, createdAt: new Date(), ...create };
          blockStore.set(key, created);
          return created;
        }),
      },
      profile: { findUnique: vi.fn() },
      $transaction: vi.fn(async (fn: any) => fn(prisma)),
    };
    (prisma as any)._store = connectionStore;
    (prisma as any)._blockStore = blockStore;

    service = new ConnectionsService(prisma, storage as any);
  });

  function seed(connection: ReturnType<typeof makeConnection>) {
    prisma._store.set(connection.id, connection);
  }

  describe('decline', () => {
    it('closes a connection the caller is a party to', async () => {
      seed(makeConnection({ status: 'MUTUAL_INTEREST' }));
      const result = await service.decline('user-a', 'conn-1');
      expect(result.status).toBe('CLOSED');
    });

    it('is idempotent against an already-closed connection', async () => {
      seed(makeConnection({ status: 'CLOSED' }));
      const result = await service.decline('user-a', 'conn-1');
      expect(result.status).toBe('CLOSED');
    });

    it('throws NotFoundException for a nonexistent connection', async () => {
      await expect(service.decline('user-a', 'nope')).rejects.toThrow(NotFoundException);
    });

    it('throws ForbiddenException when the caller is not a party', async () => {
      seed(makeConnection());
      await expect(service.decline('someone-else', 'conn-1')).rejects.toThrow(ForbiddenException);
    });
  });

  describe('markSnapDone', () => {
    it('transitions MUTUAL_INTEREST -> SNAP_PENDING on the first confirmation, matched:false', async () => {
      seed(makeConnection({ status: 'MUTUAL_INTEREST' }));
      const result = await service.markSnapDone('user-a', 'conn-1');
      expect(result.connection.status).toBe('SNAP_PENDING');
      expect(result.connection.userASnapDone).toBe(true);
      expect(result.matched).toBe(false);
    });

    it('transitions to AUTHENTICATED_MATCH, matched:true, only once both sides confirm', async () => {
      seed(makeConnection({ status: 'SNAP_PENDING', userASnapDone: true }));
      const result = await service.markSnapDone('user-b', 'conn-1');
      expect(result.connection.status).toBe('AUTHENTICATED_MATCH');
      expect(result.matched).toBe(true);
    });

    it('a retry after AUTHENTICATED_MATCH is a harmless no-op, never matched:true again', async () => {
      seed(makeConnection({ status: 'AUTHENTICATED_MATCH', userASnapDone: true, userBSnapDone: true }));
      const result = await service.markSnapDone('user-b', 'conn-1');
      expect(result.connection.status).toBe('AUTHENTICATED_MATCH');
      expect(result.matched).toBe(false);
    });

    it('throws ForbiddenException when called before MUTUAL_INTEREST', async () => {
      seed(makeConnection({ status: 'SUGGESTED' }));
      await expect(service.markSnapDone('user-a', 'conn-1')).rejects.toThrow(ForbiddenException);
    });

    it('throws ForbiddenException on a CLOSED connection', async () => {
      seed(makeConnection({ status: 'CLOSED' }));
      await expect(service.markSnapDone('user-a', 'conn-1')).rejects.toThrow(ForbiddenException);
    });

    it('throws ForbiddenException when the caller is not a party', async () => {
      seed(makeConnection());
      await expect(service.markSnapDone('someone-else', 'conn-1')).rejects.toThrow(ForbiddenException);
    });

    it('throws NotFoundException for a nonexistent connection', async () => {
      await expect(service.markSnapDone('user-a', 'nope')).rejects.toThrow(NotFoundException);
    });
  });

  describe('getReveal', () => {
    it("returns the OTHER party's displayName and a signed photoUrl", async () => {
      seed(makeConnection({ status: 'MUTUAL_INTEREST' }));
      prisma.profile.findUnique = vi.fn(async () => ({
        userId: 'user-b',
        displayName: 'Jordan',
        photoUrl: 'photos/jordan.jpg',
      }));

      const result = await service.getReveal('user-a', 'conn-1');

      expect(prisma.profile.findUnique).toHaveBeenCalledWith({ where: { userId: 'user-b' } });
      expect(result).toEqual({
        userId: 'user-b',
        displayName: 'Jordan',
        photoUrl: 'https://signed.example.com/photos/jordan.jpg',
      });
    });

    it('returns a null photoUrl when the other party has no photo yet', async () => {
      seed(makeConnection({ status: 'MUTUAL_INTEREST' }));
      prisma.profile.findUnique = vi.fn(async () => ({ userId: 'user-b', displayName: 'Jordan', photoUrl: null }));

      const result = await service.getReveal('user-a', 'conn-1');
      expect(result.photoUrl).toBeNull();
    });

    it('throws ForbiddenException before MUTUAL_INTEREST (still SUGGESTED)', async () => {
      seed(makeConnection({ status: 'SUGGESTED' }));
      await expect(service.getReveal('user-a', 'conn-1')).rejects.toThrow(ForbiddenException);
    });

    it('throws ForbiddenException when the caller is not a party', async () => {
      seed(makeConnection());
      await expect(service.getReveal('someone-else', 'conn-1')).rejects.toThrow(ForbiddenException);
    });

    it('throws NotFoundException for a nonexistent connection', async () => {
      await expect(service.getReveal('user-a', 'nope')).rejects.toThrow(NotFoundException);
    });

    it('throws ForbiddenException once BLOCKED, even if the pair was revealed before blocking', async () => {
      seed(makeConnection({ status: 'BLOCKED' }));
      await expect(service.getReveal('user-a', 'conn-1')).rejects.toThrow(ForbiddenException);
    });
  });

  describe('createSuggestion', () => {
    it('creates a new SUGGESTED connection for an unblocked pair', async () => {
      const connection = await service.createSuggestion('user-a', 'user-b');
      expect(connection.status).toBe('SUGGESTED');
    });

    it('is idempotent -- calling it again for the same pair returns the same row, never a duplicate', async () => {
      const first = await service.createSuggestion('user-a', 'user-b');
      const second = await service.createSuggestion('user-a', 'user-b');
      expect(second.id).toBe(first.id);
    });

    it('throws ForbiddenException when the pair has blocked each other (defense in depth for discovery/decide)', async () => {
      await service.block('user-b', 'user-a');
      await expect(service.createSuggestion('user-a', 'user-b')).rejects.toThrow(ForbiddenException);
    });
  });

  describe('block', () => {
    it('creates a Block row and forces a BLOCKED status on an existing connection', async () => {
      seed(makeConnection({ status: 'MUTUAL_INTEREST' }));
      const { block, connection } = await service.block('user-a', 'user-b');
      expect(block.blockerId).toBe('user-a');
      expect(block.blockedId).toBe('user-b');
      expect(connection.status).toBe('BLOCKED');
    });

    it('creates a BLOCKED connection even when no Connection row existed yet', async () => {
      const { connection } = await service.block('user-a', 'user-b');
      expect(connection.status).toBe('BLOCKED');
      expect([connection.userAId, connection.userBId].sort()).toEqual(['user-a', 'user-b']);
    });

    it('is idempotent: blocking the same pair twice does not create a second Block row', async () => {
      await service.block('user-a', 'user-b');
      await service.block('user-a', 'user-b');
      const blocks = [...(prisma as any)._blockStore.values()];
      expect(blocks).toHaveLength(1);
    });

    it('overrides an AUTHENTICATED_MATCH/ACTIVE connection to BLOCKED -- reveal/messaging having happened does not grandfather anything in', async () => {
      seed(makeConnection({ status: 'ACTIVE' }));
      const { connection } = await service.block('user-a', 'user-b');
      expect(connection.status).toBe('BLOCKED');
    });

    it('throws BadRequestException when a user tries to block themselves', async () => {
      await expect(service.block('user-a', 'user-a')).rejects.toThrow(BadRequestException);
    });
  });
});
