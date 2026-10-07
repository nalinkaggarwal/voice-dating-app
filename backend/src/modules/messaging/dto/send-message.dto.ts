import { IsEnum, IsInt, IsString, Max, MaxLength, Min, MinLength, ValidateIf } from 'class-validator';
import { MessageType } from '@prisma/client';

// Enforced by the global ValidationPipe (src/validation.ts) since the
// post-WP6 validation pass -- a TEXT message without textContent, or a
// VOICE one over 60s, is now a 400 before it reaches the service.
// MessagingService.validateSendDto() stays as a second line of defence
// for any caller that bypasses the HTTP layer.
export class SendMessageDto {
  @IsEnum(MessageType)
  type!: MessageType;

  @ValidateIf((o: SendMessageDto) => o.type === MessageType.TEXT)
  @IsString()
  @MinLength(1)
  @MaxLength(2000)
  textContent?: string;

  @ValidateIf((o: SendMessageDto) => o.type === MessageType.VOICE)
  @IsString()
  audioUrl?: string;

  @ValidateIf((o: SendMessageDto) => o.type === MessageType.VOICE)
  @IsInt()
  @Min(1)
  @Max(60)
  audioDurationSec?: number;
}
