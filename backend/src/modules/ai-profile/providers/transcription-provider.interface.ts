// Real vendor (Whisper API, Deepgram, etc.) is still TBD from the client
// -- kept deliberately generic so swapping the real implementation in is
// a same-day change, not a rework. Nothing outside this file/its
// implementations should import a concrete vendor SDK.
export interface TranscriptionProvider {
  /** audioKey is the S3 object key -- the provider is responsible for
   * fetching the audio itself (e.g. via a signed GET URL) if the real
   * vendor needs the bytes rather than a reference. */
  transcribe(audioKey: string): Promise<string>;
}

export const TRANSCRIPTION_PROVIDER = 'TRANSCRIPTION_PROVIDER';
