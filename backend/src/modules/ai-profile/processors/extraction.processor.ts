import { Inject, Logger } from '@nestjs/common';
import { Processor, WorkerHost } from '@nestjs/bullmq';
import type { Job } from 'bullmq';
import { PrismaService } from '../../../shared/prisma/prisma.service.js';
import { EXTRACTION_QUEUE, type ExtractionJobData } from '../queue.constants.js';
import {
  EXTRACTION_PROVIDER,
  type ProfileExtractionProvider,
} from '../providers/extraction-provider.interface.js';

// EXTRACTING -> DRAFT_READY | FAILED. Every ProfileClaim created here
// starts unapproved (approved: false, the Prisma default) -- there is
// deliberately no path from this processor straight to "visible to other
// users" or "used for matching" (guardrail #3 on the interface).
@Processor(EXTRACTION_QUEUE)
export class ExtractionProcessor extends WorkerHost {
  private readonly logger = new Logger(ExtractionProcessor.name);

  constructor(
    private readonly prisma: PrismaService,
    @Inject(EXTRACTION_PROVIDER) private readonly provider: ProfileExtractionProvider,
  ) {
    super();
  }

  async process(job: Job<ExtractionJobData>): Promise<void> {
    const { voiceAnswerId } = job.data;

    const voiceAnswer = await this.prisma.voiceAnswer.findUnique({ where: { id: voiceAnswerId } });
    if (!voiceAnswer) {
      this.logger.warn(`VoiceAnswer ${voiceAnswerId} not found -- skipping (already deleted?)`);
      return;
    }
    if (!voiceAnswer.transcript) {
      throw new Error(`VoiceAnswer ${voiceAnswerId} has no transcript to extract from`);
    }

    await this.prisma.voiceAnswer.update({
      where: { id: voiceAnswerId },
      data: { status: 'EXTRACTING' },
    });

    try {
      const draftClaims = await this.provider.extract(voiceAnswer.transcript);

      const profile = await this.prisma.profile.findUnique({ where: { userId: voiceAnswer.userId } });
      if (!profile) {
        throw new Error(`No Profile row for user ${voiceAnswer.userId} -- basic info must be set first`);
      }

      await this.prisma.$transaction([
        this.prisma.profileClaim.createMany({
          data: draftClaims.map((c) => ({
            profileId: profile.id,
            voiceAnswerId,
            text: c.text,
            sourceSpan: c.sourceSpan,
          })),
        }),
        this.prisma.voiceAnswer.update({
          where: { id: voiceAnswerId },
          data: { status: 'DRAFT_READY' },
        }),
      ]);
    } catch (error) {
      const reason = error instanceof Error ? error.message : 'Unknown extraction error';
      await this.prisma.voiceAnswer.update({
        where: { id: voiceAnswerId },
        data: { status: 'FAILED', failureReason: reason },
      });
      throw error;
    }
  }
}
