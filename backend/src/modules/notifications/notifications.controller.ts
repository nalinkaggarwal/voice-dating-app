import { Controller } from '@nestjs/common';
import { NotificationsService } from './notifications.service.js';

// WP1 stub -- no routes yet. Exists so the module boundary and DI wiring
// are already in place when real endpoints land.
@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}
}
