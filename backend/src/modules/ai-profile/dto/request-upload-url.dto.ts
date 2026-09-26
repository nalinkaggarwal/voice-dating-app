import { IsIn, IsString } from 'class-validator';

const ALLOWED_AUDIO_TYPES = ['audio/webm', 'audio/mp4', 'audio/mpeg', 'audio/wav'] as const;

export class RequestVoiceUploadUrlDto {
  @IsString()
  @IsIn(ALLOWED_AUDIO_TYPES)
  contentType!: (typeof ALLOWED_AUDIO_TYPES)[number];
}
