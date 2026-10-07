import { Module } from '@nestjs/common';
import { IdentityModule } from '../identity/identity.module.js';
import { NotificationsModule } from '../notifications/notifications.module.js';
import { LiveSnapController } from './live-snap.controller.js';
import { LiveSnapService } from './live-snap.service.js';

@Module({
  imports: [IdentityModule, NotificationsModule], // AccessTokenGuard; WP7 Live Snap invite push
  controllers: [LiveSnapController],
  providers: [LiveSnapService],
  exports: [LiveSnapService], // RealtimeGateway calls markActive/endSession from signaling events
})
export class LiveSnapModule {}
