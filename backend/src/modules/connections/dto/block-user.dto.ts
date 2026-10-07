import { IsString, MinLength } from 'class-validator';

// NOTE: no ValidationPipe is registered anywhere in this app (see
// messaging's send-message.dto.ts for the same caveat) -- these
// decorators don't actually run yet. ConnectionsController checks for a
// missing/empty blockedUserId by hand instead of relying on this.
export class BlockUserDto {
  @IsString()
  @MinLength(1)
  blockedUserId!: string;
}
