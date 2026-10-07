import { ForbiddenException } from '@nestjs/common';
import { AdminGuard } from './admin.guard.js';

describe('AdminGuard', () => {
  function makeContext(userId: string) {
    return {
      switchToHttp: () => ({ getRequest: () => ({ userId }) }),
    } as any;
  }

  it('throws ForbiddenException for a non-admin user', async () => {
    const prisma = { user: { findUnique: vi.fn(async () => ({ id: 'user-1', isAdmin: false })) } };
    const guard = new AdminGuard(prisma as any);
    await expect(guard.canActivate(makeContext('user-1'))).rejects.toThrow(ForbiddenException);
  });

  it('throws ForbiddenException when the user no longer exists', async () => {
    const prisma = { user: { findUnique: vi.fn(async () => null) } };
    const guard = new AdminGuard(prisma as any);
    await expect(guard.canActivate(makeContext('gone'))).rejects.toThrow(ForbiddenException);
  });

  it('allows access for isAdmin:true', async () => {
    const prisma = { user: { findUnique: vi.fn(async () => ({ id: 'admin-1', isAdmin: true })) } };
    const guard = new AdminGuard(prisma as any);
    await expect(guard.canActivate(makeContext('admin-1'))).resolves.toBe(true);
  });
});
