import { Controller } from '@nestjs/common';
import { ProfileService } from './profile.service.js';

// WP1 stub -- no routes yet. Exists so the module boundary and DI wiring
// are already in place when real endpoints land.
@Controller('profile')
export class ProfileController {
  constructor(private readonly profileService: ProfileService) {}
}
