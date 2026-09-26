import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DecisionType, VoiceAnswerStatus } from '@prisma/client';
import { PrismaService } from '../../shared/prisma/prisma.service.js';
import { StorageService } from '../../shared/storage/storage.service.js';
import { ConnectionsService } from '../connections/connections.service.js';

export interface TodayQueueEntryView {
  id: string;
  reasonText: string;
  queueDate: Date;
  sequenceInDay: number;
  /** Signed, time-limited GET URL of the candidate's latest approved
   * voice recording -- null if they don't have one (shouldn't happen for
   * an ACTIVE candidate, but the client should tolerate it).
   *
   * LAUNCH-BLOCKING RULE, not a style choice: this is the ONLY
   * candidate-identifying thing exposed here. No name, no photo, no
   * userId -- "hear before you see" is the app's entire premise (see
   * README's opening line), and a candidate's photo/identity leaking
   * into the pre-decision payload would defeat it even if the mobile UI
   * never renders it. Enforced by this interface only ever HAVING these
   * four fields (see discovery.service.spec.ts's guardrail test), not by
   * trusting every caller to remember not to add more.
   */
  voiceClipUrl: string | null;
}

@Injectable()
export class DiscoveryService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly connections: ConnectionsService,
    private readonly storage: StorageService,
  ) {}

  /**
   * Shapes each queue entry with exactly what's allowed pre-decision: the
   * reason text and a signed voice clip URL. Deliberately does NOT join
   * in Profile at all (not displayName, not photoUrl) -- there is no
   * "fetch it but don't send it" step to get wrong, because the data
   * powering this response never leaves the DB in the first place.
   */
  async today(userId: string): Promise<TodayQueueEntryView[]> {
    const entries = await this.prisma.discoveryQueueEntry.findMany({
      where: { userId, decision: null },
      orderBy: [{ queueDate: 'desc' }, { sequenceInDay: 'asc' }],
    });
    if (entries.length === 0) return [];

    const candidateIds = [...new Set(entries.map((e) => e.candidateId))];
    const voiceAnswers = await this.prisma.voiceAnswer.findMany({
      where: { userId: { in: candidateIds }, status: VoiceAnswerStatus.USER_APPROVED },
      orderBy: { updatedAt: 'desc' },
    });

    // First (most recent, thanks to the orderBy above) approved voice
    // answer per candidate wins -- a candidate could in principle have
    // more than one across re-recordings.
    const latestVoiceAnswerByUserId = new Map<string, (typeof voiceAnswers)[number]>();
    for (const voiceAnswer of voiceAnswers) {
      if (!latestVoiceAnswerByUserId.has(voiceAnswer.userId)) {
        latestVoiceAnswerByUserId.set(voiceAnswer.userId, voiceAnswer);
      }
    }

    return Promise.all(
      entries.map(async (entry) => {
        const voiceAnswer = latestVoiceAnswerByUserId.get(entry.candidateId);
        const voiceClipUrl = voiceAnswer?.audioUrl
          ? await this.storage.getDownloadUrl(voiceAnswer.audioUrl)
          : null;
        return {
          id: entry.id,
          reasonText: entry.reasonText,
          queueDate: entry.queueDate,
          sequenceInDay: entry.sequenceInDay,
          voiceClipUrl,
        };
      }),
    );
  }

  /**
   * Idempotent by construction, not by a read-then-check: the UPDATE
   * itself is guarded on `decision: null` in its WHERE clause (same
   * pattern as WP2's advanceUserStatus), so if two requests race on the
   * same entry, exactly ONE of them gets `count === 1` and proceeds to
   * fire the Connections side effect -- the other sees `count === 0` and
   * returns the already-decided row untouched. A plain
   * "read decision, then write if null" would have a race window where
   * both requests read null before either writes.
   *
   * Returns `matched: true` only when THIS call is the one that flipped
   * the Connection to MUTUAL_INTEREST -- the client uses this to decide
   * whether to show the "You matched!" screen. A retry/race loser (or a
   * PASS) always gets `matched: false`, even if the connection is
   * mutual by the time it reads the entry back -- otherwise a duplicate
   * request could show the match screen twice for one real event.
   */
  async decide(userId: string, entryId: string, decision: DecisionType) {
    const entry = await this.prisma.discoveryQueueEntry.findUnique({ where: { id: entryId } });
    if (!entry) throw new NotFoundException('Discovery queue entry not found');
    if (entry.userId !== userId) {
      throw new ForbiddenException('This discovery queue entry does not belong to you');
    }

    const { count } = await this.prisma.discoveryQueueEntry.updateMany({
      where: { id: entryId, decision: null },
      data: { decision, decidedAt: new Date() },
    });

    if (count === 0) {
      // Already decided (this call lost the race, or is a plain retry) --
      // return the existing state rather than re-deciding or erroring.
      const existing = await this.prisma.discoveryQueueEntry.findUnique({ where: { id: entryId } });
      return { entry: existing, matched: false };
    }

    let matched = false;
    if (decision === DecisionType.INTERESTED) {
      const connection = await this.connections.createSuggestion(userId, entry.candidateId);
      const updated = await this.connections.markInterested(userId, connection.id);
      matched = updated.status === 'MUTUAL_INTEREST';
    }
    // PASS: no Connection side effects at all, per the brief.

    const updatedEntry = await this.prisma.discoveryQueueEntry.findUnique({ where: { id: entryId } });
    return { entry: updatedEntry, matched };
  }
}
