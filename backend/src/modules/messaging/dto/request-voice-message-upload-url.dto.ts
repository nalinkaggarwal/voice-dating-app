import { IsIn, IsString } from 'class-validator';

// Same allowed set as ai-profile's voice answers (request-upload-url.dto.ts)
// -- kept as its own copy rather than imported cross-module, same as every
// other module here defines its own DTOs even where the shape matches.
const ALLOWED_AUDIO_TYPES = ['audio/webm', 'audio/mp4', 'audio/mpeg', 'audio/wav'] as const;

export class RequestVoiceMessageUploadUrlDto {
  @IsString()
  @IsIn(ALLOWED_AUDIO_TYPES)
  contentType!: (typeof ALLOWED_AUDIO_TYPES)[number];
}
