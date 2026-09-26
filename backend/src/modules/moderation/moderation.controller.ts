import { Controller } from '@nestjs/common';
import { ModerationService } from './moderation.service.js';

// WP1 stub -- no routes yet. Exists so the module boundary and DI wiring
// are already in place when real endpoints land.
@Controller('moderation')
export class ModerationController {
  constructor(private readonly moderationService: ModerationService) {}
}
