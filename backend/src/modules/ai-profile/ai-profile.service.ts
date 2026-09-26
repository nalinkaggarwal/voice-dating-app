import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import type { Queue } from 'bullmq';
import { PrismaService } from '../../shared/prisma/prisma.service.js';
import { StorageService } from '../../shared/storage/storage.service.js';
import { advanceUserStatus } from '../../shared/onboarding/advance-status.util.js';
import { TRANSCRIPTION_QUEUE, type TranscriptionJobData } from './queue.constants.js';

const EXTENSION_BY_CONTENT_TYPE: Record<string, string> = {
  'audio/webm': 'webm',
  'audio/mp4': 'm4a',
  'audio/mpeg': 'mp3',
  'audio/wav': 'wav',
};

@Injectable()
export class AiProfileService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    @InjectQueue(TRANSCRIPTION_QUEUE) private readonly transcriptionQueue: Queue<TranscriptionJobData>,
  ) {}

  async requestVoiceUploadUrl(contentType: string): Promise<{ uploadUrl: string; key: string }> {
    const extension = EXTENSION_BY_CONTENT_TYPE[contentType] ?? 'bin';
    const key = this.storage.generateKey('voice', extension);
    const uploadUrl = await this.storage.getUploadUrl(key, contentType);
    return { uploadUrl, key };
  }

  // Called once the client has finished the direct-to-S3 PUT. Creates the
  // VoiceAnswer row (status UPLOADED) and kicks off the pipeline --
  // matches the brief's step 2 exactly (the row doesn't exist before this).
  async completeVoiceUpload(userId: string, key: string) {
    const voiceAnswer = await this.prisma.voiceAnswer.create({
      data: { userId, audioUrl: key, status: 'UPLOADED' },
    });

    await this.transcriptionQueue.add('transcribe', { voiceAnswerId: voiceAnswer.id });

    await advanceUserStatus(
      this.prisma,
      userId,
      ['INTENT_DONE'], // VOICE_RECORDED is next after the intent step
      'VOICE_RECORDED',
    );

    return voiceAnswer;
  }

  async getVoiceAnswer(userId: string, voiceAnswerId: string) {
    const voiceAnswer = await this.prisma.voiceAnswer.findUnique({
      where: { id: voiceAnswerId },
      include: { claims: { where: { discarded: false }, orderBy: { createdAt: 'asc' } } },
    });
    if (!voiceAnswer || voiceAnswer.userId !== userId) {
      throw new NotFoundException('Voice answer not found');
    }
    return voiceAnswer;
  }

  private async getOwnedClaim(userId: string, claimId: string) {
    const claim = await this.prisma.profileClaim.findUnique({
      where: { id: claimId },
      include: { voiceAnswer: true },
    });
    if (!claim || claim.voiceAnswer.userId !== userId) {
      throw new NotFoundException('Claim not found');
    }
    return claim;
  }

  async editClaim(userId: string, claimId: string, text: string) {
    const claim = await this.getOwnedClaim(userId, claimId);
    if (claim.voiceAnswer.status !== 'DRAFT_READY') {
      throw new ForbiddenException('This claim is no longer editable');
    }
    return this.prisma.profileClaim.update({ where: { id: claimId }, data: { text } });
  }

  async approveClaim(userId: string, claimId: string) {
    await this.getOwnedClaim(userId, claimId);
    // Idempotent: approving an already-approved claim is a no-op success.
    return this.prisma.profileClaim.update({
      where: { id: claimId },
      data: { approved: true, discarded: false },
    });
  }

  async discardClaim(userId: string, claimId: string) {
    await this.getOwnedClaim(userId, claimId);
    return this.prisma.profileClaim.update({
      where: { id: claimId },
      data: { discarded: true, approved: false },
    });
  }

  // User is done reviewing (however many claims they chose to approve) --
  // locks the draft in. Matches the brief's step 7: VoiceAnswer ->
  // USER_APPROVED, User.status -> AI_REVIEW_DONE.
  async finalizeReview(userId: string, voiceAnswerId: string) {
    const voiceAnswer = await this.prisma.voiceAnswer.findUnique({ where: { id: voiceAnswerId } });
    if (!voiceAnswer || voiceAnswer.userId !== userId) {
      throw new NotFoundException('Voice answer not found');
    }
    if (voiceAnswer.status !== 'DRAFT_READY') {
      throw new ForbiddenException(
        `Cannot finalize a voice answer in status ${voiceAnswer.status} -- must be DRAFT_READY`,
      );
    }

    const updated = await this.prisma.voiceAnswer.update({
      where: { id: voiceAnswerId },
      data: { status: 'USER_APPROVED' },
    });

    await advanceUserStatus(this.prisma, userId, ['VOICE_RECORDED'], 'AI_REVIEW_DONE');

    return updated;
  }
}
