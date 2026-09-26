import { Controller } from '@nestjs/common';
import { AiProfileService } from './ai-profile.service.js';

// WP1 stub -- no routes yet. Exists so the module boundary and DI wiring
// are already in place when real endpoints land.
@Controller('ai-profile')
export class AiProfileController {
  constructor(private readonly aiProfileService: AiProfileService) {}
}
