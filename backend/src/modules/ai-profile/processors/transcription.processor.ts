import { Inject, Logger } from '@nestjs/common';
import { Processor, WorkerHost, InjectQueue } from '@nestjs/bullmq';
import type { Job, Queue } from 'bullmq';
import { PrismaService } from '../../../shared/prisma/prisma.service.js';
import {
  EXTRACTION_QUEUE,
  TRANSCRIPTION_QUEUE,
  type ExtractionJobData,
  type TranscriptionJobData,
} from '../queue.constants.js';
import {
  TRANSCRIPTION_PROVIDER,
  type TranscriptionProvider,
} from '../providers/transcription-provider.interface.js';

// One job per VoiceAnswer: TRANSCRIBING -> (TRANSCRIBED + enqueue
// extraction) | FAILED. The extraction step is a SEPARATE queue/job (per
// the brief's pipeline design), not chained inline here, so either stage
// can be retried/scaled independently.
@Processor(TRANSCRIPTION_QUEUE)
export class TranscriptionProcessor extends WorkerHost {
  private readonly logger = new Logger(TranscriptionProcessor.name);

  constructor(
    private readonly prisma: PrismaService,
    @Inject(TRANSCRIPTION_PROVIDER) private readonly provider: TranscriptionProvider,
    @InjectQueue(EXTRACTION_QUEUE) private readonly extractionQueue: Queue<ExtractionJobData>,
  ) {
    super();
  }

  async process(job: Job<TranscriptionJobData>): Promise<void> {
    const { voiceAnswerId } = job.data;

    const voiceAnswer = await this.prisma.voiceAnswer.findUnique({ where: { id: voiceAnswerId } });
    if (!voiceAnswer) {
      this.logger.warn(`VoiceAnswer ${voiceAnswerId} not found -- skipping (already deleted?)`);
      return;
    }

    await this.prisma.voiceAnswer.update({
      where: { id: voiceAnswerId },
      data: { status: 'TRANSCRIBING' },
    });

    try {
      const transcript = await this.provider.transcribe(voiceAnswer.audioUrl);
      await this.prisma.voiceAnswer.update({
        where: { id: voiceAnswerId },
        data: { status: 'TRANSCRIBED', transcript },
      });
      await this.extractionQueue.add('extract', { voiceAnswerId });
    } catch (error) {
      const reason = error instanceof Error ? error.message : 'Unknown transcription error';
      await this.prisma.voiceAnswer.update({
        where: { id: voiceAnswerId },
        data: { status: 'FAILED', failureReason: reason },
      });
      throw error; // let BullMQ record the job as failed
    }
  }
}
