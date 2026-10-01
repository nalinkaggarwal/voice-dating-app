import { Module } from '@nestjs/common';
import { StorageModule } from '../../shared/storage/storage.module.js';
import { IdentityModule } from '../identity/identity.module.js';
import { RealtimeModule } from '../realtime/realtime.module.js';
import { MessagingController } from './messaging.controller.js';
import { MessagingService } from './messaging.service.js';

// WP5: text/voice chat once a Connection is AUTHENTICATED_MATCH/ACTIVE.
@Module({
  imports: [
    StorageModule, // signed voice-message upload/download URLs
    IdentityModule, // AccessTokenGuard
    RealtimeModule, // broadcasts message:* events through RealtimeGateway
  ],
  controllers: [MessagingController],
  providers: [MessagingService],
  exports: [MessagingService],
})
export class MessagingModule {}
