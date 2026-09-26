import { Inject, Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../../shared/prisma/prisma.service.js';
import { EligibilityService } from './eligibility.service.js';
import { DiscoveryConfigService } from './discovery-config.service.js';
import { rankCandidates } from './ranking.util.js';
import {
  REASON_GENERATION_PROVIDER,
  type ReasonGenerationProvider,
} from './providers/reason-generation-provider.interface.js';

/** Normalizes to midnight UTC -- queueDate represents a DAY, not a
 * timestamp. Without this, two calls a few hours apart (e.g. a retried
 * cron run) would store slightly different DateTime values and the
 * (userId, queueDate, sequenceInDay) unique constraint would never
 * actually catch a duplicate-for-today. */
export function startOfUtcDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

@Injectable()
export class QueueGenerationService {
  private readonly logger = new Logger(QueueGenerationService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly eligibility: EligibilityService,
    private readonly discoveryConfig: DiscoveryConfigService,
    @Inject(REASON_GENERATION_PROVIDER) private readonly reasonProvider: ReasonGenerationProvider,
  ) {}

  private async approvedClaimTextsFor(userId: string): Promise<string[]> {
    const profile = await this.prisma.profile.findUnique({ where: { userId } });
    if (!profile) return [];
    const claims = await this.prisma.profileClaim.findMany({
      where: { profileId: profile.id, approved: true, discarded: false },
      select: { text: true },
    });
    return claims.map((c) => c.text);
  }

  /**
   * Idempotent per (userId, queueDate): if this user already has their
   * full tier-limit's worth of entries for the day, this is a no-op --
   * a rerun (retry, a second cron trigger) never double-generates. If
   * PARTIALLY generated (e.g. a crash mid-loop on a premium user with
   * limit > 1), tops up only the missing slots rather than starting over.
   */
  async generateForUser(userId: string, queueDate: Date): Promise<number> {
    const normalizedDate = startOfUtcDay(queueDate);

    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user || user.status !== 'ACTIVE') return 0;

    const [limit, existingEntries] = await Promise.all([
      this.discoveryConfig.dailyLimitFor(user.tier),
      this.prisma.discoveryQueueEntry.findMany({
        where: { userId, queueDate: normalizedDate },
        select: { candidateId: true, sequenceInDay: true },
      }),
    ]);

    const remainingSlots = limit - existingEntries.length;
    if (remainingSlots <= 0) return 0;

    const alreadyQueuedIds = new Set(existingEntries.map((e) => e.candidateId));
    const eligible = (await this.eligibility.eligibleCandidatesFor(userId)).filter(
      (c) => !alreadyQueuedIds.has(c.userId),
    );
    if (eligible.length === 0) return 0;

    const [viewerClaims, viewerPreference] = await Promise.all([
      this.approvedClaimTextsFor(userId),
      this.prisma.preference.findUnique({ where: { userId } }),
    ]);
    const candidateClaimsById = new Map<string, string[]>();
    for (const candidate of eligible) {
      candidateClaimsById.set(candidate.userId, await this.approvedClaimTextsFor(candidate.userId));
    }

    const ranked = rankCandidates(
      viewerClaims,
      viewerPreference?.relationshipIntent ?? null,
      eligible.map((c) => ({
        userId: c.userId,
        approvedClaimTexts: candidateClaimsById.get(c.userId)!,
        relationshipIntent: c.relationshipIntent,
      })),
    );

    const nextSequence = existingEntries.length; // 0-indexed, continues from wherever we left off
    let created = 0;

    for (let i = 0; i < Math.min(remainingSlots, ranked.length); i++) {
      const candidate = ranked[i];
      const reasonText = await this.reasonProvider.generate({
        overlappingTerms: candidate.overlappingTerms,
        viewerClaimTexts: viewerClaims,
        candidateClaimTexts: candidateClaimsById.get(candidate.candidateUserId)!,
      });

      try {
        await this.prisma.discoveryQueueEntry.create({
          data: {
            userId,
            candidateId: candidate.candidateUserId,
            reasonText,
            queueDate: normalizedDate,
            sequenceInDay: nextSequence + i,
          },
        });
        created++;
      } catch (error) {
        // Unique constraint hit -- a concurrent generation run (e.g. two
        // overlapping cron triggers) already filled this exact slot.
        // Not an error worth surfacing; the slot IS filled, which is the
        // actual goal.
        const message = error instanceof Error ? error.message : String(error);
        this.logger.warn(`Discovery entry creation race for user ${userId}, slot ${nextSequence + i}: ${message}`);
      }
    }

    return created;
  }

  async generateForAllActiveUsers(queueDate: Date = new Date()): Promise<{
    usersProcessed: number;
    entriesCreated: number;
  }> {
    const activeUsers = await this.prisma.user.findMany({
      where: { status: 'ACTIVE' },
      select: { id: true },
    });

    let entriesCreated = 0;
    for (const user of activeUsers) {
      entriesCreated += await this.generateForUser(user.id, queueDate);
    }

    this.logger.log(
      `Discovery generation: ${activeUsers.length} active users processed, ${entriesCreated} entries created`,
    );
    return { usersProcessed: activeUsers.length, entriesCreated };
  }
}
