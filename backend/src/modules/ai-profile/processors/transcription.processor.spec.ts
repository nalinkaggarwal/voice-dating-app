import type { Job } from 'bullmq';
import { TranscriptionProcessor } from './transcription.processor.js';
import type { TranscriptionJobData } from '../queue.constants.js';

function fakeJob(data: TranscriptionJobData): Job<TranscriptionJobData> {
  return { data } as Job<TranscriptionJobData>;
}

describe('TranscriptionProcessor', () => {
  let prisma: any;
  let provider: { transcribe: ReturnType<typeof vi.fn> };
  let extractionQueue: { add: ReturnType<typeof vi.fn> };
  let processor: TranscriptionProcessor;

  beforeEach(() => {
    prisma = {
      voiceAnswer: {
        findUnique: vi.fn(async () => ({ id: 'va-1', audioUrl: 'voice/key.webm', userId: 'user-1' })),
        update: vi.fn(async () => ({})),
      },
    };
    provider = { transcribe: vi.fn(async () => 'a real transcript') };
    extractionQueue = { add: vi.fn(async () => {}) };

    processor = new TranscriptionProcessor(prisma, provider as any, extractionQueue as any);
  });

  it('on success: TRANSCRIBING -> TRANSCRIBED with the transcript, then enqueues extraction', async () => {
    await processor.process(fakeJob({ voiceAnswerId: 'va-1' }));

    expect(prisma.voiceAnswer.update).toHaveBeenNthCalledWith(1, {
      where: { id: 'va-1' },
      data: { status: 'TRANSCRIBING' },
    });
    expect(prisma.voiceAnswer.update).toHaveBeenNthCalledWith(2, {
      where: { id: 'va-1' },
      data: { status: 'TRANSCRIBED', transcript: 'a real transcript' },
    });
    expect(extractionQueue.add).toHaveBeenCalledWith('extract', { voiceAnswerId: 'va-1' });
  });

  it('on provider failure: sets FAILED + failureReason and rethrows for BullMQ to record', async () => {
    provider.transcribe.mockRejectedValueOnce(new Error('vendor exploded'));

    await expect(processor.process(fakeJob({ voiceAnswerId: 'va-1' }))).rejects.toThrow(
      'vendor exploded',
    );

    expect(prisma.voiceAnswer.update).toHaveBeenNthCalledWith(2, {
      where: { id: 'va-1' },
      data: { status: 'FAILED', failureReason: 'vendor exploded' },
    });
    expect(extractionQueue.add).not.toHaveBeenCalled();
  });

  it('skips gracefully (no throw) if the VoiceAnswer row no longer exists', async () => {
    prisma.voiceAnswer.findUnique.mockResolvedValueOnce(null);
    await expect(processor.process(fakeJob({ voiceAnswerId: 'gone' }))).resolves.toBeUndefined();
    expect(prisma.voiceAnswer.update).not.toHaveBeenCalled();
  });
});
