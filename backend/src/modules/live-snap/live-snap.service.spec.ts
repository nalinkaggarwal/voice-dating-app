import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { LiveSnapService } from './live-snap.service.js';

describe('LiveSnapService', () => {
  let service: LiveSnapService;
  let prisma: any;
  let notifications: Record<string, ReturnType<typeof vi.fn>>;

  function makeConnection(overrides: Record<string, any> = {}) {
    return { id: 'conn-1', userAId: 'user-a', userBId: 'user-b', status: 'MUTUAL_INTEREST', ...overrides };
  }

  function makeSession(overrides: Record<string, any> = {}) {
    return {
      id: 'session-1',
      connectionId: 'conn-1',
      status: 'RINGING',
      startedAt: new Date('2026-10-01T10:00:00Z'),
      endedAt: null,
      ...overrides,
    };
  }

  beforeEach(() => {
    prisma = {
      connection: { findUnique: vi.fn(async () => makeConnection()) },
      block: { findFirst: vi.fn(async () => null) },
      liveSnapSession: {
        findFirst: vi.fn(async () => null),
        create: vi.fn(async ({ data }: any) => makeSession(data)),
        updateMany: vi.fn(async () => ({ count: 1 })),
      },
    };
    notifications = {
      notifyNewMessage: vi.fn(async () => ({ requested: 0, delivered: 0, failed: 0, forgotten: 0 })),
      notifyMutualMatch: vi.fn(async () => ({ requested: 0, delivered: 0, failed: 0, forgotten: 0 })),
      notifyLiveSnapInvite: vi.fn(async () => ({ requested: 0, delivered: 0, failed: 0, forgotten: 0 })),
      notifyAuthenticatedMatch: vi.fn(async () => ({ requested: 0, delivered: 0, failed: 0, forgotten: 0 })),
    };
    service = new LiveSnapService(prisma, notifications as any);
  });

  describe('startSession', () => {
    it('creates a new RINGING session when none is in flight', async () => {
      const result = await service.startSession('user-a', 'conn-1');
      expect(prisma.liveSnapSession.create).toHaveBeenCalledWith({ data: { connectionId: 'conn-1' } });
      expect(result.status).toBe('RINGING');
    });

    it('returns the existing session instead of creating a second one when a call is already in flight', async () => {
      const existing = makeSession({ status: 'ACTIVE' });
      prisma.liveSnapSession.findFirst = vi.fn(async () => existing);

      const result = await service.startSession('user-a', 'conn-1');

      expect(prisma.liveSnapSession.create).not.toHaveBeenCalled();
      expect(result).toBe(existing);
    });

    it('allows starting from SNAP_PENDING (a retried call after one side already confirmed)', async () => {
      prisma.connection.findUnique = vi.fn(async () => makeConnection({ status: 'SNAP_PENDING' }));
      const result = await service.startSession('user-a', 'conn-1');
      expect(result.status).toBe('RINGING');
    });

    it('throws ForbiddenException before MUTUAL_INTEREST', async () => {
      prisma.connection.findUnique = vi.fn(async () => makeConnection({ status: 'SUGGESTED' }));
      await expect(service.startSession('user-a', 'conn-1')).rejects.toThrow(ForbiddenException);
    });

    it('throws ForbiddenException on an already-AUTHENTICATED_MATCH connection', async () => {
      prisma.connection.findUnique = vi.fn(async () => makeConnection({ status: 'AUTHENTICATED_MATCH' }));
      await expect(service.startSession('user-a', 'conn-1')).rejects.toThrow(ForbiddenException);
    });

    it('throws ForbiddenException when the caller is not a party', async () => {
      await expect(service.startSession('someone-else', 'conn-1')).rejects.toThrow(ForbiddenException);
    });

    it('rejects starting a new session when the pair is blocked, even though Connection.status is MUTUAL_INTEREST (defense in depth)', async () => {
      prisma.block.findFirst = vi.fn(async () => ({ id: 'block-1', blockerId: 'user-b', blockedId: 'user-a' }));
      await expect(service.startSession('user-a', 'conn-1')).rejects.toThrow(ForbiddenException);
    });

    it('throws NotFoundException for a nonexistent connection', async () => {
      prisma.connection.findUnique = vi.fn(async () => null);
      await expect(service.startSession('user-a', 'nope')).rejects.toThrow(NotFoundException);
    });
  });

  describe('getSession', () => {
    it("returns the connection's latest session", async () => {
      const session = makeSession();
      prisma.liveSnapSession.findFirst = vi.fn(async () => session);

      const result = await service.getSession('user-a', 'conn-1');

      expect(prisma.liveSnapSession.findFirst).toHaveBeenCalledWith({
        where: { connectionId: 'conn-1' },
        orderBy: { startedAt: 'desc' },
      });
      expect(result).toBe(session);
    });

    it('throws ForbiddenException when the caller is not a party', async () => {
      await expect(service.getSession('someone-else', 'conn-1')).rejects.toThrow(ForbiddenException);
    });
  });

  describe('markActive', () => {
    it('flips a RINGING session to ACTIVE', async () => {
      await service.markActive('session-1');
      expect(prisma.liveSnapSession.updateMany).toHaveBeenCalledWith({
        where: { id: 'session-1', status: 'RINGING' },
        data: { status: 'ACTIVE' },
      });
    });
  });

  describe('endSession', () => {
    it('flips a RINGING or ACTIVE session to ENDED with a timestamp', async () => {
      await service.endSession('session-1');
      expect(prisma.liveSnapSession.updateMany).toHaveBeenCalledWith({
        where: { id: 'session-1', status: { in: ['RINGING', 'ACTIVE'] } },
        data: { status: 'ENDED', endedAt: expect.any(Date) },
      });
    });
  });

  describe('WP7 push hooks', () => {
    it('rings the OTHER party when a new session is created', async () => {
      await service.startSession('user-a', 'conn-1');
      expect(notifications.notifyLiveSnapInvite).toHaveBeenCalledTimes(1);
      expect(notifications.notifyLiveSnapInvite).toHaveBeenCalledWith('user-b', { connectionId: 'conn-1', callerId: 'user-a' });
    });

    it('does not ring again for a re-tap while a session is already RINGING/ACTIVE', async () => {
      prisma.liveSnapSession.findFirst = vi.fn(async () => makeSession());
      await service.startSession('user-a', 'conn-1');
      expect(notifications.notifyLiveSnapInvite).not.toHaveBeenCalled();
    });

    it('does not ring when the start is rejected (wrong status)', async () => {
      prisma.connection.findUnique = vi.fn(async () => makeConnection({ status: 'ACTIVE' }));
      await expect(service.startSession('user-a', 'conn-1')).rejects.toThrow();
      expect(notifications.notifyLiveSnapInvite).not.toHaveBeenCalled();
    });
  });
});
