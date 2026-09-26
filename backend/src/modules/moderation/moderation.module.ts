import { Module } from '@nestjs/common';
import { ModerationController } from './moderation.controller.js';
import { ModerationService } from './moderation.service.js';

// WP1 stub module -- see module docstring in the kickoff brief for scope.
@Module({
  controllers: [ModerationController],
  providers: [ModerationService],
  exports: [ModerationService],
})
export class ModerationModule {}
