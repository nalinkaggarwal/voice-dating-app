import { BadRequestException, NotFoundException } from '@nestjs/common';
import { ModerationService } from './moderation.service.js';

describe('ModerationService', () => {
  let service: ModerationService;
  let prisma: any;

  function makeReport(overrides: Record<string, any> = {}) {
    return {
      id: 'report-1',
      reporterId: 'user-a',
      reportedUserId: 'user-b',
      reason: 'SPAM',
      context: 'PROFILE',
      contextId: null,
      details: null,
      status: 'PENDING',
      createdAt: new Date('2026-10-01T10:00:00Z'),
      reviewedAt: null,
      reviewedBy: null,
      decision: null,
      ...overrides,
    };
  }

  beforeEach(() => {
    const reportStore = new Map<string, any>();
    let nextId = 1;
    prisma = {
      report: {
        create: vi.fn(async ({ data }: any) => {
          const report = makeReport({ id: `report-${nextId++}`, ...data });
          reportStore.set(report.id, report);
          return report;
        }),
        findMany: vi.fn(async ({ where }: any = {}) => {
          return [...reportStore.values()].filter((r) => {
            if (where?.status && r.status !== where.status) return false;
            if (where?.context && r.context !== where.context) return false;
            return true;
          });
        }),
        findUnique: vi.fn(async ({ where: { id } }: any) => reportStore.get(id) ?? null),
        update: vi.fn(async ({ where: { id }, data }: any) => {
          const updated = { ...reportStore.get(id), ...data };
          reportStore.set(id, updated);
          return updated;
        }),
      },
    };
    (prisma as any)._store = reportStore;
    service = new ModerationService(prisma);
  });

  function seed(report: ReturnType<typeof makeReport>) {
    prisma._store.set(report.id, report);
  }

  describe('report', () => {
    it('creates a PENDING report without touching the Block table at all', async () => {
      const report = await service.report('user-a', { reportedUserId: 'user-b', reason: 'SPAM', context: 'PROFILE' });
      expect(report.status).toBe('PENDING');
      expect(prisma.report.create).toHaveBeenCalledTimes(1);
      // No block-related model is even on this mock Prisma -- if
      // report() tried to touch one, this test would throw, not just
      // silently pass.
    });

    it('throws BadRequestException when a user tries to report themselves', async () => {
      await expect(
        service.report('user-a', { reportedUserId: 'user-a', reason: 'SPAM', context: 'PROFILE' }),
      ).rejects.toThrow(BadRequestException);
    });
  });

  describe('listReports priority ordering', () => {
    it('ranks a LIVE_SNAP-context report above a NORMAL one regardless of creation order', async () => {
      seed(makeReport({ id: 'r-old-normal', reason: 'SPAM', context: 'PROFILE', createdAt: new Date('2026-10-01T09:00:00Z') }));
      seed(makeReport({ id: 'r-new-livesnap', reason: 'OTHER', context: 'LIVE_SNAP', createdAt: new Date('2026-10-01T11:00:00Z') }));

      const results = await service.listReports();

      expect(results[0].id).toBe('r-new-livesnap');
      expect(results[0].priority).toBe('HIGH');
      expect(results[1].priority).toBe('NORMAL');
    });

    it('ranks a SAFETY_CONCERN reason as HIGH even outside a LIVE_SNAP context', async () => {
      seed(makeReport({ id: 'r-safety', reason: 'SAFETY_CONCERN', context: 'MESSAGE' }));
      const results = await service.listReports();
      expect(results[0].priority).toBe('HIGH');
    });

    it('orders oldest-first within the same priority tier (FIFO)', async () => {
      seed(makeReport({ id: 'r-newer', createdAt: new Date('2026-10-01T12:00:00Z') }));
      seed(makeReport({ id: 'r-older', createdAt: new Date('2026-10-01T08:00:00Z') }));

      const results = await service.listReports();

      expect(results.map((r) => r.id)).toEqual(['r-older', 'r-newer']);
    });

    it('filters by the computed priority even though it is not a DB column', async () => {
      seed(makeReport({ id: 'r-normal', reason: 'SPAM', context: 'PROFILE' }));
      seed(makeReport({ id: 'r-high', reason: 'SAFETY_CONCERN', context: 'MESSAGE' }));

      const results = await service.listReports({ priority: 'HIGH' });

      expect(results.map((r) => r.id)).toEqual(['r-high']);
    });
  });

  describe('getReport', () => {
    it('throws NotFoundException for a nonexistent report', async () => {
      await expect(service.getReport('nope')).rejects.toThrow(NotFoundException);
    });
  });

  describe('actionReport', () => {
    it('stamps reviewedAt/reviewedBy and updates status on assign/action', async () => {
      seed(makeReport({ status: 'PENDING' }));
      const result = await service.actionReport('report-1', 'admin-1', { status: 'ACTIONED', decision: 'Profile removed' });
      expect(result.status).toBe('ACTIONED');
      expect(result.reviewedBy).toBe('admin-1');
      expect(result.decision).toBe('Profile removed');
      expect(result.reviewedAt).toBeInstanceOf(Date);
    });

    it('dismiss is just actionReport with status DISMISSED', async () => {
      seed(makeReport({ status: 'PENDING' }));
      const result = await service.actionReport('report-1', 'admin-1', { status: 'DISMISSED' });
      expect(result.status).toBe('DISMISSED');
    });

    it('throws NotFoundException for a nonexistent report', async () => {
      await expect(service.actionReport('nope', 'admin-1', { status: 'DISMISSED' })).rejects.toThrow(NotFoundException);
    });
  });
});
