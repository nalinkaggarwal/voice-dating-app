import { Injectable, Logger } from '@nestjs/common';
import type { TranscriptionProvider } from './transcription-provider.interface.js';

// WP2 dev/test stub: returns fixed dummy text instead of calling a real
// STT vendor, so the whole pipeline (queue -> transcribe -> extract ->
// review) is testable end-to-end with no API key. audioKey is intentionally
// ignored -- a real provider would fetch the audio and actually transcribe
// it; this exists purely to exercise the pipeline's state machine.
@Injectable()
export class MockTranscriptionProvider implements TranscriptionProvider {
  private readonly logger = new Logger(MockTranscriptionProvider.name);

  async transcribe(audioKey: string): Promise<string> {
    this.logger.log(`[MOCK STT] "transcribing" ${audioKey}`);
    return (
      'I love hiking on weekends and trying new coffee shops around the city. ' +
      "I'm looking for someone who enjoys deep conversations as much as spontaneous road trips. " +
      'My friends would say I always bring snacks on every trip.'
    );
  }
}
