import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { AiProfileService } from './ai-profile.service.js';

describe('AiProfileService', () => {
  let service: AiProfileService;
  let prisma: any;
  let storage: { generateKey: ReturnType<typeof vi.fn>; getUploadUrl: ReturnType<typeof vi.fn> };
  let queue: { add: ReturnType<typeof vi.fn> };

  beforeEach(() => {
    prisma = {
      voiceAnswer: {
        create: vi.fn(async ({ data }: any) => ({ id: 'va-1', ...data })),
        findUnique: vi.fn(),
        findFirst: vi.fn(),
        update: vi.fn(async ({ data }: any) => ({ id: 'va-1', ...data })),
      },
      profileClaim: {
        findUnique: vi.fn(),
        update: vi.fn(async ({ data }: any) => ({ id: 'claim-1', ...data })),
      },
      user: { updateMany: vi.fn(async () => ({ count: 1 })) },
    };
    storage = {
      generateKey: vi.fn(() => 'voice/abc.webm'),
      getUploadUrl: vi.fn(async () => 'https://s3.example.com/signed-put'),
    };
    queue = { add: vi.fn(async () => {}) };

    service = new AiProfileService(prisma, storage as any, queue as any);
  });

  describe('requestVoiceUploadUrl', () => {
    it('generates a key and returns a signed PUT URL', async () => {
      const result = await service.requestVoiceUploadUrl('audio/webm');
      expect(result).toEqual({ uploadUrl: 'https://s3.example.com/signed-put', key: 'voice/abc.webm' });
      expect(storage.generateKey).toHaveBeenCalledWith('voice', 'webm');
    });
  });

  describe('completeVoiceUpload', () => {
    it('creates the VoiceAnswer row, enqueues transcription, and advances status', async () => {
      const result = await service.completeVoiceUpload('user-1', 'voice/abc.webm');

      expect(prisma.voiceAnswer.create).toHaveBeenCalledWith({
        data: { userId: 'user-1', audioUrl: 'voice/abc.webm', status: 'UPLOADED' },
      });
      expect(queue.add).toHaveBeenCalledWith('transcribe', { voiceAnswerId: 'va-1' });
      expect(prisma.user.updateMany).toHaveBeenCalledWith({
        where: { id: 'user-1', status: { in: ['INTENT_DONE'] } },
        data: { status: 'VOICE_RECORDED' },
      });
      expect(result.id).toBe('va-1');
    });
  });

  describe('getVoiceAnswer', () => {
    it('returns the voice answer when owned by the caller', async () => {
      prisma.voiceAnswer.findUnique.mockResolvedValueOnce({ id: 'va-1', userId: 'user-1', claims: [] });
      const result = await service.getVoiceAnswer('user-1', 'va-1');
      expect(result.id).toBe('va-1');
    });

    it('throws NotFoundException for someone else\'s voice answer', async () => {
      prisma.voiceAnswer.findUnique.mockResolvedValueOnce({ id: 'va-1', userId: 'someone-else' });
      await expect(service.getVoiceAnswer('user-1', 'va-1')).rejects.toThrow(NotFoundException);
    });

    it('throws NotFoundException for a nonexistent voice answer', async () => {
      prisma.voiceAnswer.findUnique.mockResolvedValueOnce(null);
      await expect(service.getVoiceAnswer('user-1', 'nope')).rejects.toThrow(NotFoundException);
    });
  });

  describe('getLatestVoiceAnswer', () => {
    it('returns the caller\'s most recent voice answer', async () => {
      prisma.voiceAnswer.findFirst.mockResolvedValueOnce({ id: 'va-2', userId: 'user-1', claims: [] });
      const result = await service.getLatestVoiceAnswer('user-1');
      expect(result.id).toBe('va-2');
      expect(prisma.voiceAnswer.findFirst).toHaveBeenCalledWith({
        where: { userId: 'user-1' },
        orderBy: { createdAt: 'desc' },
        include: { claims: { where: { discarded: false }, orderBy: { createdAt: 'asc' } } },
      });
    });

    it('throws NotFoundException when the caller has never recorded one', async () => {
      prisma.voiceAnswer.findFirst.mockResolvedValueOnce(null);
      await expect(service.getLatestVoiceAnswer('user-1')).rejects.toThrow(NotFoundException);
    });
  });

  describe('editClaim', () => {
    it('allows editing while DRAFT_READY', async () => {
      prisma.profileClaim.findUnique.mockResolvedValueOnce({
        id: 'claim-1',
        voiceAnswer: { userId: 'user-1', status: 'DRAFT_READY' },
      });
      const result = await service.editClaim('user-1', 'claim-1', 'edited text');
      expect(result.text).toBe('edited text');
    });

    it('rejects editing once the voice answer has moved past DRAFT_READY', async () => {
      prisma.profileClaim.findUnique.mockResolvedValueOnce({
        id: 'claim-1',
        voiceAnswer: { userId: 'user-1', status: 'USER_APPROVED' },
      });
      await expect(service.editClaim('user-1', 'claim-1', 'x')).rejects.toThrow(ForbiddenException);
    });

    it('rejects editing a claim owned by someone else', async () => {
      prisma.profileClaim.findUnique.mockResolvedValueOnce({
        id: 'claim-1',
        voiceAnswer: { userId: 'someone-else', status: 'DRAFT_READY' },
      });
      await expect(service.editClaim('user-1', 'claim-1', 'x')).rejects.toThrow(NotFoundException);
    });
  });

  describe('approveClaim / discardClaim', () => {
    beforeEach(() => {
      prisma.profileClaim.findUnique.mockResolvedValue({
        id: 'claim-1',
        voiceAnswer: { userId: 'user-1', status: 'DRAFT_READY' },
      });
    });

    it('approve sets approved true, discarded false', async () => {
      const result = await service.approveClaim('user-1', 'claim-1');
      expect(result).toMatchObject({ approved: true, discarded: false });
    });

    it('discard sets discarded true, approved false', async () => {
      const result = await service.discardClaim('user-1', 'claim-1');
      expect(result).toMatchObject({ discarded: true, approved: false });
    });

    it('approving twice is a harmless no-op (idempotent)', async () => {
      await service.approveClaim('user-1', 'claim-1');
      await expect(service.approveClaim('user-1', 'claim-1')).resolves.toMatchObject({
        approved: true,
      });
    });
  });

  describe('finalizeReview', () => {
    it('transitions USER_APPROVED and advances User.status to AI_REVIEW_DONE', async () => {
      prisma.voiceAnswer.findUnique.mockResolvedValueOnce({
        id: 'va-1',
        userId: 'user-1',
        status: 'DRAFT_READY',
      });

      await service.finalizeReview('user-1', 'va-1');

      expect(prisma.voiceAnswer.update).toHaveBeenCalledWith({
        where: { id: 'va-1' },
        data: { status: 'USER_APPROVED' },
      });
      expect(prisma.user.updateMany).toHaveBeenCalledWith({
        where: { id: 'user-1', status: { in: ['VOICE_RECORDED'] } },
        data: { status: 'AI_REVIEW_DONE' },
      });
    });

    it('rejects finalizing before the draft is ready', async () => {
      prisma.voiceAnswer.findUnique.mockResolvedValueOnce({
        id: 'va-1',
        userId: 'user-1',
        status: 'TRANSCRIBING',
      });
      await expect(service.finalizeReview('user-1', 'va-1')).rejects.toThrow(ForbiddenException);
    });

    it('rejects finalizing a voice answer owned by someone else', async () => {
      prisma.voiceAnswer.findUnique.mockResolvedValueOnce({
        id: 'va-1',
        userId: 'someone-else',
        status: 'DRAFT_READY',
      });
      await expect(service.finalizeReview('user-1', 'va-1')).rejects.toThrow(NotFoundException);
    });
  });
});
