import { IsEnum, IsInt, IsString, Max, MaxLength, Min, MinLength, ValidateIf } from 'class-validator';
import { MessageType } from '@prisma/client';

// NOTE: no ValidationPipe is registered anywhere in this app (checked
// main.ts/app.module.ts) -- these decorators don't actually run yet, same
// as every other DTO across WP1-4. MessagingService validates type-
// specific fields itself (see sendMessage) rather than relying on this.
// Left here so validation starts working for free the day someone wires
// up the pipe, instead of needing this file touched too.
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
