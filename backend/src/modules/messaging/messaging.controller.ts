import { Controller } from '@nestjs/common';
import { MessagingService } from './messaging.service.js';

// WP1 stub -- no routes yet. Exists so the module boundary and DI wiring
// are already in place when real endpoints land.
@Controller('messaging')
export class MessagingController {
  constructor(private readonly messagingService: MessagingService) {}
}
