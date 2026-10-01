import { ForbiddenException, Injectable, NotFoundException, NotImplementedException } from '@nestjs/common';
import type { Connection } from '@prisma/client';
import { PrismaService } from '../../shared/prisma/prisma.service.js';
import { StorageService } from '../../shared/storage/storage.service.js';

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
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
  ) {}

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

  // Either party declines -> status CLOSED. The mutation itself is a
  // guarded updateMany (not read-then-write) so a double-decline race
  // between both parties can't do anything worse than both setting the
  // same terminal state -- same "guard the UPDATE, don't just guard the
  // read" philosophy as advanceUserStatus/decide(). The upfront read is
  // only for the NotFound/Forbidden authorization checks, which need a
  // row in hand regardless.
  async decline(userId: string, connectionId: string): Promise<Connection> {
    const connection = await this.prisma.connection.findUnique({ where: { id: connectionId } });
    if (!connection) throw new NotFoundException('Connection not found');
    if (connection.userAId !== userId && connection.userBId !== userId) {
      throw new ForbiddenException('You are not a party to this connection');
    }
    await this.prisma.connection.updateMany({
      where: { id: connectionId, status: { notIn: ['CLOSED', 'BLOCKED'] } },
      data: { status: 'CLOSED' },
    });
    return (await this.prisma.connection.findUnique({ where: { id: connectionId } }))!;
  }

  // userId confirms their side of a completed Live Snap call for this
  // connection. Mirrors markInterested's shape exactly (set this user's
  // flag, re-check both inside the same transaction, conditionally
  // transition) but for the SnapDone flags instead of Interested:
  // MUTUAL_INTEREST -> SNAP_PENDING on the first confirmation,
  // SNAP_PENDING -> AUTHENTICATED_MATCH once both are in.
  //
  // Returns `matched: true` only on the call that actually flips the
  // status to AUTHENTICATED_MATCH -- same "only the flipping call gets
  // true" rule discovery.service.ts's decide() uses, so a client retry
  // (network flake after a successful confirm) can never re-show the
  // "you're authenticated" screen. Unlike decide(), there's no outer
  // write-once entity protecting against that retry here, so the
  // protection has to live in this method itself: a connection already
  // at AUTHENTICATED_MATCH/ACTIVE short-circuits to a harmless no-op
  // instead of re-running the flag logic. Anything before MUTUAL_INTEREST
  // or a terminal CLOSED/BLOCKED connection is a genuine misuse and
  // throws, rather than silently setting a flag that can never do
  // anything.
  async markSnapDone(
    userId: string,
    connectionId: string,
  ): Promise<{ connection: Connection; matched: boolean }> {
    return this.prisma.$transaction(async (tx) => {
      const connection = await tx.connection.findUnique({ where: { id: connectionId } });
      if (!connection) throw new NotFoundException('Connection not found');
      if (connection.userAId !== userId && connection.userBId !== userId) {
        throw new ForbiddenException('You are not a party to this connection');
      }

      if (connection.status === 'AUTHENTICATED_MATCH' || connection.status === 'ACTIVE') {
        return { connection, matched: false };
      }
      if (connection.status !== 'MUTUAL_INTEREST' && connection.status !== 'SNAP_PENDING') {
        throw new ForbiddenException(`Cannot confirm Live Snap while status is ${connection.status}`);
      }

      const isUserA = connection.userAId === userId;
      const updated = await tx.connection.update({
        where: { id: connectionId },
        data: isUserA ? { userASnapDone: true } : { userBSnapDone: true },
      });

      if (updated.userASnapDone && updated.userBSnapDone) {
        const matchedConnection = await tx.connection.update({
          where: { id: connectionId },
          data: { status: 'AUTHENTICATED_MATCH' },
        });
        return { connection: matchedConnection, matched: true };
      }
      if (updated.status === 'MUTUAL_INTEREST') {
        const pending = await tx.connection.update({
          where: { id: connectionId },
          data: { status: 'SNAP_PENDING' },
        });
        return { connection: pending, matched: false };
      }
      return { connection: updated, matched: false };
    });
  }

  // The matched user's name + photo, revealed for the first time now that
  // there's a real mutual match -- "hear before you see" only governs the
  // pre-decision discovery payload (TodayQueueEntryView, see
  // discovery.service.ts), not what's shown after both sides are already
  // in. 403 before MUTUAL_INTEREST: nothing to reveal yet.
  async getReveal(
    userId: string,
    connectionId: string,
  ): Promise<{ displayName: string | null; photoUrl: string | null }> {
    const connection = await this.prisma.connection.findUnique({ where: { id: connectionId } });
    if (!connection) throw new NotFoundException('Connection not found');
    if (connection.userAId !== userId && connection.userBId !== userId) {
      throw new ForbiddenException('You are not a party to this connection');
    }
    if (connection.status === 'SUGGESTED') {
      throw new ForbiddenException('Not matched yet');
    }

    const otherUserId = connection.userAId === userId ? connection.userBId : connection.userAId;
    const profile = await this.prisma.profile.findUnique({ where: { userId: otherUserId } });
    const photoUrl = profile?.photoUrl ? await this.storage.getDownloadUrl(profile.photoUrl) : null;
    return { displayName: profile?.displayName ?? null, photoUrl };
  }

  // TODO(WP3+): moderation/trust-safety escalation -> status BLOCKED.
  // Idempotent, and must be reachable from any prior status.
  async block(_userId: string, _connectionId: string): Promise<never> {
    throw new NotImplementedException('block lands in WP3');
  }
}
