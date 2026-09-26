import { MockTranscriptionProvider } from './mock-transcription.provider.js';

describe('MockTranscriptionProvider', () => {
  it('returns non-empty dummy text regardless of the audio key', async () => {
    const provider = new MockTranscriptionProvider();
    const result = await provider.transcribe('voice/some-key.webm');
    expect(typeof result).toBe('string');
    expect(result.length).toBeGreaterThan(0);
  });
});
