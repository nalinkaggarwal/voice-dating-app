import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import type { Block, Connection } from '@prisma/client';
import { PrismaService } from '../../shared/prisma/prisma.service.js';
import { StorageService } from '../../shared/storage/storage.service.js';
import { isBlocked } from '../../shared/moderation/block.util.js';
import { NotificationsService } from '../notifications/notifications.service.js';

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
    private readonly notifications: NotificationsService,
  ) {}

  // Create a SUGGESTED connection from the discovery/matching pipeline.
  // Idempotent on (userAId, userBId) via upsert against the schema's own
  // unique constraint -- calling this again for a pair that already has
  // a row (in ANY status) just returns the existing row untouched, never
  // duplicates or errors.
  async createSuggestion(userAId: string, userBId: string): Promise<Connection> {
    // Defense in depth: EligibilityService already excludes a blocked
    // pair from ever being surfaced as a discovery candidate, but this is
    // the one place EVERY caller that could create/progress a Connection
    // (today just discovery's decide()) funnels through, so a block is
    // enforced here too rather than relying solely on the filter upstream.
    if (await isBlocked(this.prisma, userAId, userBId)) {
      throw new ForbiddenException('Cannot create a connection between blocked users');
    }
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
    const { connection, becameMutual } = await this.prisma.$transaction(async (tx) => {
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
        const mutual = await tx.connection.update({
          where: { id: connectionId },
          data: { status: 'MUTUAL_INTEREST' },
        });
        return { connection: mutual, becameMutual: true };
      }
      return { connection: updated, becameMutual: false };
    });

    if (becameMutual) {
      // WP7: the "it's a match" push, closing the WP1-era TODO that lived
      // inside the guarded branch above. Fired only by the single call that
      // flipped SUGGESTED -> MUTUAL_INTEREST (so it can never double-send),
      // and only AFTER the transaction commits (so a rollback can't leave a
      // push for a match that never happened). The caller already knows --
      // decide() returns `matched` -- so the OTHER party is the recipient.
      const otherUserId = connection.userAId === userId ? connection.userBId : connection.userAId;
      await this.notifications.notifyMutualMatch(otherUserId, { connectionId, otherUserId: userId });
    }
    return connection;
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
    const result = await this.prisma.$transaction(async (tx) => {
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

    if (result.matched) {
      // WP7: only the call that flipped to AUTHENTICATED_MATCH gets here
      // (the early return above makes every later call a no-op), and only
      // after commit. Names are allowed at this point -- both parties have
      // been through Reveal and a live call together.
      const otherUserId = result.connection.userAId === userId ? result.connection.userBId : result.connection.userAId;
      await this.notifications.notifyAuthenticatedMatch(otherUserId, { connectionId, otherUserId: userId });
    }
    return result;
  }

  // The matched user's name + photo, revealed for the first time now that
  // there's a real mutual match -- "hear before you see" only governs the
  // pre-decision discovery payload (TodayQueueEntryView, see
  // discovery.service.ts), not what's shown after both sides are already
  // in. 403 before MUTUAL_INTEREST: nothing to reveal yet.
  async getReveal(
    userId: string,
    connectionId: string,
  ): Promise<{ userId: string; displayName: string | null; photoUrl: string | null }> {
    const connection = await this.prisma.connection.findUnique({ where: { id: connectionId } });
    if (!connection) throw new NotFoundException('Connection not found');
    if (connection.userAId !== userId && connection.userBId !== userId) {
      throw new ForbiddenException('You are not a party to this connection');
    }
    if (connection.status === 'SUGGESTED') {
      throw new ForbiddenException('Not matched yet');
    }
    // A prior reveal doesn't grandfather in access -- blocking cuts this
    // off immediately too, same as it does for messaging.
    if (connection.status === 'BLOCKED') {
      throw new ForbiddenException('This connection is no longer available');
    }

    const otherUserId = connection.userAId === userId ? connection.userBId : connection.userAId;
    const profile = await this.prisma.profile.findUnique({ where: { userId: otherUserId } });
    const photoUrl = profile?.photoUrl ? await this.storage.getDownloadUrl(profile.photoUrl) : null;
    // Included so the client can address a block()/report() call against
    // this specific person -- safe to expose here specifically (unlike
    // discovery's pre-decision payload) since revealing full identity is
    // the entire point of this step.
    return { userId: otherUserId, displayName: profile?.displayName ?? null, photoUrl };
  }

  // blockerId blocks blockedId, by USER id rather than connectionId --
  // unlike every other method here, a block is reachable even if no
  // Connection row exists yet between this pair. One transaction: upsert
  // the Block row (idempotent on its own unique constraint -- blocking
  // twice is a harmless no-op) AND force any Connection between them
  // (existing or not) to BLOCKED, unconditionally overriding whatever
  // status it was in -- "immediately, everywhere" per the spec, not a
  // guarded transition off a specific prior status like every other
  // transition in this file. Reused by every other surface (messaging,
  // Live Snap, discovery/connections) via shared/moderation's isBlocked
  // helper, which checks the Block row directly rather than only trusting
  // Connection.status.
  async block(blockerId: string, blockedId: string): Promise<{ block: Block; connection: Connection }> {
    if (blockerId === blockedId) {
      throw new BadRequestException('Cannot block yourself');
    }

    return this.prisma.$transaction(async (tx) => {
      const block = await tx.block.upsert({
        where: { blockerId_blockedId: { blockerId, blockedId } },
        create: { blockerId, blockedId },
        update: {},
      });

      const [a, b] = canonicalPair(blockerId, blockedId);
      const connection = await tx.connection.upsert({
        where: { userAId_userBId: { userAId: a, userBId: b } },
        create: { userAId: a, userBId: b, status: 'BLOCKED' },
        update: { status: 'BLOCKED' },
      });

      return { block, connection };
    });
  }

  // The caller's own "people I've blocked" list -- there's no separate
  // "who blocked me" surface (nothing in the product needs it, and
  // exposing it would defeat the point of a block), so this only ever
  // queries blocksMade, never the inverse relation.
  async listBlocked(userId: string): Promise<Block[]> {
    return this.prisma.block.findMany({ where: { blockerId: userId }, orderBy: { createdAt: 'desc' } });
  }
}
