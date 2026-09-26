import { Injectable, NotImplementedException } from '@nestjs/common';
import { PrismaService } from '../../shared/prisma/prisma.service.js';

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

  // TODO(WP3): create a SUGGESTED connection from the discovery/matching
  // pipeline. Idempotent on (userAId, userBId) -- must not error or
  // duplicate if a suggestion already exists for this pair.
  async createSuggestion(_userAId: string, _userBId: string): Promise<never> {
    throw new NotImplementedException('createSuggestion lands in WP3');
  }

  // TODO(WP3): userId marks interest in connectionId. Transaction must:
  //   1. Set this user's *Interested flag to true (idempotent no-op if
  //      already true).
  //   2. Re-read both flags inside the SAME transaction.
  //   3. If both are now true, transition status -> MUTUAL_INTEREST and
  //      trigger the "it's a match" notification exactly once (guard on
  //      the status transition itself, not on the notification send, so
  //      a retry after the transition already happened can't re-notify).
  async markInterested(_userId: string, _connectionId: string): Promise<never> {
    throw new NotImplementedException('markInterested lands in WP3');
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
