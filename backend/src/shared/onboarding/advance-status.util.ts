import type { UserStatus } from '@prisma/client';
import type { PrismaService } from '../prisma/prisma.service.js';

/**
 * Moves User.status forward ONLY if it's currently one of `allowedFrom`.
 * The current-status check lives in the WHERE clause of a single
 * UPDATE, not a separate read-then-write -- so this is both atomic (no
 * race between two concurrent requests advancing the same user) and
 * idempotent (a retry after the status has already moved past
 * `allowedFrom` matches zero rows and is a safe no-op), the same
 * guarantee WP1's Connections state machine rules require of every
 * transition.
 */
export async function advanceUserStatus(
  prisma: PrismaService,
  userId: string,
  allowedFrom: UserStatus[],
  to: UserStatus,
): Promise<void> {
  await prisma.user.updateMany({
    where: { id: userId, status: { in: allowedFrom } },
    data: { status: to },
  });
}
