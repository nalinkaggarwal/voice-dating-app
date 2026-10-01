// Shared by every module that generates an S3 key for an uploaded audio
// file (ai-profile's voice answers, WP5's voice messages) -- extracted
// once both needed the exact same mapping rather than drifting into two
// copies.
const EXTENSION_BY_CONTENT_TYPE: Record<string, string> = {
  'audio/webm': 'webm',
  'audio/mp4': 'm4a',
  'audio/mpeg': 'mp3',
  'audio/wav': 'wav',
};

export function audioExtensionForContentType(contentType: string): string {
  return EXTENSION_BY_CONTENT_TYPE[contentType] ?? 'bin';
}
