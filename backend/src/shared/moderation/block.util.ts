import type { PrismaService } from '../prisma/prisma.service.js';

// Checked directly against the Block table, independently of
// Connection.status, by every surface that needs it (messaging, Live
// Snap, connections/decide) -- defense in depth, so a block is enforced
// even if a status transition elsewhere were ever wrong or bypassed,
// not solely derived from BLOCKED having been set on some Connection
// row. Direction-agnostic: if A blocked B, this returns true for either
// argument order -- blocking is one-directional to create, but mutual
// to enforce.
export async function isBlocked(prisma: PrismaService, userIdA: string, userIdB: string): Promise<boolean> {
  const block = await prisma.block.findFirst({
    where: {
      OR: [
        { blockerId: userIdA, blockedId: userIdB },
        { blockerId: userIdB, blockedId: userIdA },
      ],
    },
  });
  return block !== null;
}
