import { Module } from '@nestjs/common';
import { AiProfileController } from './ai-profile.controller.js';
import { AiProfileService } from './ai-profile.service.js';

// WP1 stub module -- see module docstring in the kickoff brief for scope.
@Module({
  controllers: [AiProfileController],
  providers: [AiProfileService],
  exports: [AiProfileService],
})
export class AiProfileModule {}
