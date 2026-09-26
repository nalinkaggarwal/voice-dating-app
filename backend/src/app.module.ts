import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AppController } from './app.controller.js';
import { AppService } from './app.service.js';
import { PrismaModule } from './shared/prisma/prisma.module.js';
import { StorageModule } from './shared/storage/storage.module.js';
import { IdentityModule } from './modules/identity/identity.module.js';
import { ProfileModule } from './modules/profile/profile.module.js';
import { AiProfileModule } from './modules/ai-profile/ai-profile.module.js';
import { DiscoveryModule } from './modules/discovery/discovery.module.js';
import { ConnectionsModule } from './modules/connections/connections.module.js';
import { MessagingModule } from './modules/messaging/messaging.module.js';
import { RealtimeModule } from './modules/realtime/realtime.module.js';
import { ModerationModule } from './modules/moderation/moderation.module.js';
import { BillingModule } from './modules/billing/billing.module.js';
import { NotificationsModule } from './modules/notifications/notifications.module.js';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, envFilePath: '.env' }),
    PrismaModule,
    StorageModule,
    IdentityModule,
    ProfileModule,
    AiProfileModule,
    DiscoveryModule,
    ConnectionsModule,
    MessagingModule,
    RealtimeModule,
    ModerationModule,
    BillingModule,
    NotificationsModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
