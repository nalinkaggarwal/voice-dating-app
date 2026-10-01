import { Module } from '@nestjs/common';
import { IdentityModule } from '../identity/identity.module.js';
import { LiveSnapModule } from '../live-snap/live-snap.module.js';
import { RealtimeGateway } from './realtime.gateway.js';

@Module({
  imports: [
    IdentityModule, // needs TokenService to authenticate socket handshakes
    LiveSnapModule, // needs LiveSnapService for Live Snap session status updates
  ],
  providers: [RealtimeGateway],
  exports: [RealtimeGateway], // MessagingService broadcasts message:* events through it
})
export class RealtimeModule {}
