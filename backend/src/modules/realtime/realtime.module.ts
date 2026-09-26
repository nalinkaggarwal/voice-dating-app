import { Module } from '@nestjs/common';
import { IdentityModule } from '../identity/identity.module.js';
import { RealtimeGateway } from './realtime.gateway.js';

@Module({
  imports: [IdentityModule], // needs TokenService to authenticate socket handshakes
  providers: [RealtimeGateway],
})
export class RealtimeModule {}
