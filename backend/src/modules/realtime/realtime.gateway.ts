import { Logger } from '@nestjs/common';
import {
  ConnectedSocket,
  OnGatewayConnection,
  OnGatewayDisconnect,
  WebSocketGateway,
} from '@nestjs/websockets';
import type { Socket } from 'socket.io';
import { TokenService } from '../identity/token.service.js';

// WP1 skeleton only -- no chat/presence/call-signaling events yet (those
// land with the messaging and voice_date features). Wired here purely to
// prove the gateway boots and that a connection is authenticated the same
// way an HTTP request is: a valid short-lived access token, never trusted
// from an unauthenticated client.
@WebSocketGateway({ cors: true })
export class RealtimeGateway implements OnGatewayConnection, OnGatewayDisconnect {
  private readonly logger = new Logger(RealtimeGateway.name);

  constructor(private readonly tokens: TokenService) {}

  handleConnection(@ConnectedSocket() client: Socket) {
    const token = client.handshake.auth?.token as string | undefined;
    if (!token) {
      this.logger.warn(`Socket ${client.id} connected without a token — disconnecting.`);
      client.disconnect(true);
      return;
    }
    try {
      const { sub } = this.tokens.verifyAccessToken(token);
      client.data.userId = sub;
      this.logger.log(`Socket ${client.id} authenticated as user ${sub}`);
    } catch {
      this.logger.warn(`Socket ${client.id} presented an invalid/expired token — disconnecting.`);
      client.disconnect(true);
    }
  }

  handleDisconnect(@ConnectedSocket() client: Socket) {
    this.logger.log(`Socket ${client.id} disconnected`);
  }
}
