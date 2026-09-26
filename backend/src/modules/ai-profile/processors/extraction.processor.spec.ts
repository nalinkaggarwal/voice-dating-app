import type { Job } from 'bullmq';
import { ExtractionProcessor } from './extraction.processor.js';
import type { ExtractionJobData } from '../queue.constants.js';

function fakeJob(data: ExtractionJobData): Job<ExtractionJobData> {
  return { data } as Job<ExtractionJobData>;
}

describe('ExtractionProcessor', () => {
  let prisma: any;
  let provider: { extract: ReturnType<typeof vi.fn> };
  let processor: ExtractionProcessor;

  beforeEach(() => {
    prisma = {
      voiceAnswer: {
        findUnique: vi.fn(async () => ({
          id: 'va-1',
          userId: 'user-1',
          transcript: 'I love hiking. I hate mornings.',
        })),
        update: vi.fn(async () => ({})),
      },
      profile: {
        findUnique: vi.fn(async () => ({ id: 'profile-1', userId: 'user-1' })),
      },
      profileClaim: {
        createMany: vi.fn(async () => ({ count: 2 })),
      },
      $transaction: vi.fn(async (ops: Promise<any>[]) => Promise.all(ops)),
    };
    provider = {
      extract: vi.fn(async () => [
        { text: 'I love hiking.', sourceSpan: '0-15' },
        { text: 'I hate mornings.', sourceSpan: '16-33' },
      ]),
    };

    processor = new ExtractionProcessor(prisma, provider as any);
  });

  it('on success: EXTRACTING -> creates claims -> DRAFT_READY', async () => {
    await processor.process(fakeJob({ voiceAnswerId: 'va-1' }));

    expect(prisma.voiceAnswer.update).toHaveBeenNthCalledWith(1, {
      where: { id: 'va-1' },
      data: { status: 'EXTRACTING' },
    });
    expect(prisma.profileClaim.createMany).toHaveBeenCalledWith({
      data: [
        { profileId: 'profile-1', voiceAnswerId: 'va-1', text: 'I love hiking.', sourceSpan: '0-15' },
        { profileId: 'profile-1', voiceAnswerId: 'va-1', text: 'I hate mornings.', sourceSpan: '16-33' },
      ],
    });
    // The claims-create and the DRAFT_READY transition are one transaction.
    expect(prisma.$transaction).toHaveBeenCalledOnce();
  });

  it('never passes `approved` in the create payload -- relies on the schema default (false), no auto-publish path', async () => {
    await processor.process(fakeJob({ voiceAnswerId: 'va-1' }));
    const payload = prisma.profileClaim.createMany.mock.calls[0][0].data;
    for (const row of payload) {
      expect(row).not.toHaveProperty('approved');
    }
  });

  it('fails cleanly if there is no transcript yet', async () => {
    prisma.voiceAnswer.findUnique.mockResolvedValueOnce({ id: 'va-1', userId: 'user-1', transcript: null });
    await expect(processor.process(fakeJob({ voiceAnswerId: 'va-1' }))).rejects.toThrow(
      /no transcript/,
    );
  });

  it('fails cleanly if the user has no Profile row yet (basic info not submitted)', async () => {
    prisma.profile.findUnique.mockResolvedValueOnce(null);
    await expect(processor.process(fakeJob({ voiceAnswerId: 'va-1' }))).rejects.toThrow(
      /No Profile row/,
    );
    expect(prisma.voiceAnswer.update).toHaveBeenLastCalledWith({
      where: { id: 'va-1' },
      data: { status: 'FAILED', failureReason: expect.stringContaining('No Profile row') },
    });
  });

  it('on provider failure: sets FAILED + failureReason and rethrows', async () => {
    provider.extract.mockRejectedValueOnce(new Error('extraction vendor exploded'));
    await expect(processor.process(fakeJob({ voiceAnswerId: 'va-1' }))).rejects.toThrow(
      'extraction vendor exploded',
    );
    expect(prisma.voiceAnswer.update).toHaveBeenLastCalledWith({
      where: { id: 'va-1' },
      data: { status: 'FAILED', failureReason: 'extraction vendor exploded' },
    });
  });

  it('skips gracefully if the VoiceAnswer row no longer exists', async () => {
    prisma.voiceAnswer.findUnique.mockResolvedValueOnce(null);
    await expect(processor.process(fakeJob({ voiceAnswerId: 'gone' }))).resolves.toBeUndefined();
  });
});
