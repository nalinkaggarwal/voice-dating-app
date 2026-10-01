import { ForbiddenException, NotFoundException } from '@nestjs/common';
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

  beforeEach(() => {
    storage = { getDownloadUrl: vi.fn(async (key: string) => `https://signed.example.com/${key}`) };

    const connectionStore = new Map<string, any>();
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
      },
      profile: { findUnique: vi.fn() },
      $transaction: vi.fn(async (fn: any) => fn(prisma)),
    };
    (prisma as any)._store = connectionStore;

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
  });
});
