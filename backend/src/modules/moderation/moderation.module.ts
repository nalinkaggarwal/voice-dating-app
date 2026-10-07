import { Module } from '@nestjs/common';
import { IdentityModule } from '../identity/identity.module.js';
import { ModerationController } from './moderation.controller.js';
import { ModerationService } from './moderation.service.js';

// Moderation & Block: report() + the admin-facing moderation queue.
// block() itself lives on ConnectionsService, not here (it needs the
// same guarded Connection-transition machinery every other state change
// in that service already uses) -- see that service's own docstring.
@Module({
  imports: [IdentityModule], // AccessTokenGuard + AdminGuard
  controllers: [ModerationController],
  providers: [ModerationService],
  exports: [ModerationService],
})
export class ModerationModule {}
