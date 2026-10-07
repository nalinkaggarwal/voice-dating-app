import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { IdentityModule } from '../identity/identity.module.js';
import { NotificationsController } from './notifications.controller.js';
import { NotificationsService } from './notifications.service.js';
import { PUSH_PROVIDER } from './push/push-provider.interface.js';
import { buildPushProvider } from './push/push-provider.factory.js';

// WP7: push notifications. Imported by MessagingModule, ConnectionsModule
// and LiveSnapModule (the three places product events originate); imports
// nothing but Identity itself, so it can never be part of a module cycle.
@Module({
  imports: [IdentityModule], // AccessTokenGuard
  controllers: [NotificationsController],
  providers: [
    NotificationsService,
    {
      provide: PUSH_PROVIDER,
      inject: [ConfigService],
      useFactory: (config: ConfigService) => buildPushProvider(config),
    },
  ],
  exports: [NotificationsService],
})
export class NotificationsModule {}
