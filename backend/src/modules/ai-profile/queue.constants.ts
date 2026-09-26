export const TRANSCRIPTION_QUEUE = 'transcription';
export const EXTRACTION_QUEUE = 'extraction';

export interface TranscriptionJobData {
  voiceAnswerId: string;
}

export interface ExtractionJobData {
  voiceAnswerId: string;
}
