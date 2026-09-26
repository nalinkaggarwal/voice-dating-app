import { advanceUserStatus } from './advance-status.util.js';

describe('advanceUserStatus', () => {
  it('issues a single guarded UPDATE using allowedFrom in the WHERE clause', async () => {
    const prisma = { user: { updateMany: vi.fn(async () => ({ count: 1 })) } };

    await advanceUserStatus(prisma as any, 'user-1', ['ACCOUNT_CREATED'], 'BASIC_INFO_DONE');

    expect(prisma.user.updateMany).toHaveBeenCalledWith({
      where: { id: 'user-1', status: { in: ['ACCOUNT_CREATED'] } },
      data: { status: 'BASIC_INFO_DONE' },
    });
  });

  it('is a safe no-op (still just one call) regardless of whether any row actually matched', async () => {
    const prisma = { user: { updateMany: vi.fn(async () => ({ count: 0 })) } };
    await expect(
      advanceUserStatus(prisma as any, 'user-1', ['PREFERENCES_DONE'], 'INTENT_DONE'),
    ).resolves.toBeUndefined();
    expect(prisma.user.updateMany).toHaveBeenCalledOnce();
  });
});
