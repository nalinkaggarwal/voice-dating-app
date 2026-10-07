import { IsString, MinLength } from 'class-validator';

// Enforced by the global ValidationPipe (src/validation.ts) since the
// post-WP6 validation pass. Before that, nothing actually rejected a
// missing/empty blockedUserId -- the old note here claimed the controller
// did by hand; it did not. ConnectionsService.block() still rejects a
// self-block itself (that one is business logic, not shape).
export class BlockUserDto {
  @IsString()
  @MinLength(1)
  blockedUserId!: string;
}
