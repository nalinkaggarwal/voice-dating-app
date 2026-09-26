import { ForbiddenException, Injectable, NotFoundException, NotImplementedException } from '@nestjs/common';
import type { Connection } from '@prisma/client';
import { PrismaService } from '../../shared/prisma/prisma.service.js';

/** Lower-UUID-first ordering -- the ONE place this ordering rule is
 * decided, so createSuggestion/markInterested/every future caller agrees
 * on which side of a pair is "A" without duplicating the comparison. */
function canonicalPair(userAId: string, userBId: string): [string, string] {
  return userAId < userBId ? [userAId, userBId] : [userBId, userAId];
}

/**
 * State machine rules for every method in this service (WP3 implements
 * the bodies -- WP1 only fixes the method signatures and schema so
 * nothing downstream has to change shape later):
 *
 *  - Every status transition goes through an explicit method here --
 *    never a direct field update from a controller.
 *  - Every transition is one DB transaction and is idempotent: calling
 *    the same transition twice (retry, double-tap, two devices) must
 *    never create duplicate state or duplicate side effects (e.g. two
 *    "it's a match" notifications for one mutual interest).
 *  - Mutual interest only fires when BOTH userAInterested AND
 *    userBInterested are true -- check-then-set inside one transaction,
 *    not two separate reads racing each other.
 *  - Connection rows are keyed by an UNORDERED pair. Callers must always
 *    resolve (userAId, userBId) via a canonical ordering (e.g. lower
 *    UUID first) before reading or writing, so a pair can never end up
 *    with two rows for the two possible orderings.
 */
@Injectable()
export class ConnectionsService {
  constructor(private readonly prisma: PrismaService) {}

  // Create a SUGGESTED connection from the discovery/matching pipeline.
  // Idempotent on (userAId, userBId) via upsert against the schema's own
  // unique constraint -- calling this again for a pair that already has
  // a row (in ANY status) just returns the existing row untouched, never
  // duplicates or errors.
  async createSuggestion(userAId: string, userBId: string): Promise<Connection> {
    const [a, b] = canonicalPair(userAId, userBId);
    return this.prisma.connection.upsert({
      where: { userAId_userBId: { userAId: a, userBId: b } },
      create: { userAId: a, userBId: b },
      update: {}, // already exists (any status) -- no-op, idempotent
    });
  }

  // userId marks interest in connectionId. One transaction:
  //   1. Set this user's *Interested flag to true (idempotent -- setting
  //      an already-true flag to true again is a harmless no-op).
  //   2. Re-read both flags inside the SAME transaction (check-then-set,
  //      not a separate read racing another concurrent call).
  //   3. If both are now true AND status is still SUGGESTED, transition
  //      to MUTUAL_INTEREST. Guarding on `status === 'SUGGESTED'` (not
  //      just "both flags true") is what makes this idempotent against a
  //      retry: a second call after the transition already fired sees
  //      status already MUTUAL_INTEREST and skips the transition + its
  //      side effects, rather than re-firing a "match" notification.
  async markInterested(userId: string, connectionId: string): Promise<Connection> {
    return this.prisma.$transaction(async (tx) => {
      const connection = await tx.connection.findUnique({ where: { id: connectionId } });
      if (!connection) throw new NotFoundException('Connection not found');
      if (connection.userAId !== userId && connection.userBId !== userId) {
        throw new ForbiddenException('You are not a party to this connection');
      }

      const isUserA = connection.userAId === userId;
      const updated = await tx.connection.update({
        where: { id: connectionId },
        data: isUserA ? { userAInterested: true } : { userBInterested: true },
      });

      if (updated.userAInterested && updated.userBInterested && updated.status === 'SUGGESTED') {
        // TODO(WP4+): fire the "it's a match" push notification here,
        // inside this same guarded branch so it can never double-send.
        return tx.connection.update({
          where: { id: connectionId },
          data: { status: 'MUTUAL_INTEREST' },
        });
      }
      return updated;
    });
  }

  // TODO(WP3): either party declines -> status CLOSED. Idempotent:
  // closing an already-closed connection is a no-op success.
  async decline(_userId: string, _connectionId: string): Promise<never> {
    throw new NotImplementedException('decline lands in WP3');
  }

  // TODO(WP3, alongside WP4's Live Snap work): userId completes their
  // liveness check for this connection. Transaction must: set this
  // user's *SnapDone flag, and if both are now true, transition
  // MUTUAL_INTEREST -> AUTHENTICATED_MATCH (SNAP_PENDING is the interim
  // status while only one side has completed theirs).
  async markSnapDone(_userId: string, _connectionId: string): Promise<never> {
    throw new NotImplementedException('markSnapDone lands in WP4');
  }

  // TODO(WP3+): moderation/trust-safety escalation -> status BLOCKED.
  // Idempotent, and must be reachable from any prior status.
  async block(_userId: string, _connectionId: string): Promise<never> {
    throw new NotImplementedException('block lands in WP3');
  }
}
