import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { NotificationsService } from './notifications.service.js';
import { RegisterDeviceDto } from './dto/register-device.dto.js';
import { UnregisterDeviceDto } from './dto/unregister-device.dto.js';
import { AccessTokenGuard } from '../identity/guards/access-token.guard.js';
import { CurrentUserId } from '../identity/decorators/current-user.decorator.js';

// Device-token registration only. Nothing here SENDS a push -- that
// happens inside the services that own the triggering event (messaging,
// connections, live-snap), never on a client's say-so.
@Controller('notifications')
@UseGuards(AccessTokenGuard)
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  // Called by the app after every login and on every FCM token refresh.
  @Post('devices')
  registerDevice(@CurrentUserId() userId: string, @Body() dto: RegisterDeviceDto) {
    return this.notificationsService.registerDevice(userId, dto.token, dto.platform);
  }

  // POST rather than DELETE-with-body: several HTTP stacks (and proxies)
  // drop or reject a DELETE body, and the token is far too long for a URL.
  @Post('devices/unregister')
  unregisterDevice(@CurrentUserId() userId: string, @Body() dto: UnregisterDeviceDto) {
    return this.notificationsService.unregisterDevice(userId, dto.token);
  }
}
