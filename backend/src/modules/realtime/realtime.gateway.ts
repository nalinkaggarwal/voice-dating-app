import { Logger } from '@nestjs/common';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import type { Server, Socket } from 'socket.io';
import { TokenService } from '../identity/token.service.js';
import { PrismaService } from '../../shared/prisma/prisma.service.js';
import { LiveSnapService } from '../live-snap/live-snap.service.js';

interface LiveSnapRoomPayload {
  connectionId: string;
  sessionId: string;
}

interface LiveSnapSignalPayload extends LiveSnapRoomPayload {
  payload: unknown;
}

function liveSnapRoom(connectionId: string): string {
  return `liveSnap:${connectionId}`;
}

// WP1 auth skeleton + WP4 Live Snap WebRTC signaling relay. Every
// liveSnap:* event re-verifies the authenticated socket's userId is a
// party to the given connectionId -- never trusts the client's own claim
// of which connection it's calling about, same as every REST route in
// this app re-checks party membership itself rather than trusting a
// prior check.
@WebSocketGateway({ cors: true })
export class RealtimeGateway implements OnGatewayConnection, OnGatewayDisconnect {
  private readonly logger = new Logger(RealtimeGateway.name);

  @WebSocketServer()
  private readonly server!: Server;

  constructor(
    private readonly tokens: TokenService,
    private readonly prisma: PrismaService,
    private readonly liveSnap: LiveSnapService,
  ) {}

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

  // Mirrors a leave for whatever Live Snap room this socket last joined,
  // if any -- an app kill or network drop mid-call is at least as common
  // as an explicit "end call" tap, and the other party still needs to be
  // told and the session still needs to be marked ENDED either way.
  async handleDisconnect(@ConnectedSocket() client: Socket) {
    this.logger.log(`Socket ${client.id} disconnected`);
    const room = client.data.liveSnapRoom as LiveSnapRoomPayload | undefined;
    if (room) {
      client.to(liveSnapRoom(room.connectionId)).emit('liveSnap:peerLeft');
      await this.liveSnap.endSession(room.sessionId);
    }
  }

  private async verifyParty(client: Socket, connectionId: string): Promise<boolean> {
    const userId = client.data.userId as string | undefined;
    if (!userId) return false;
    const connection = await this.prisma.connection.findUnique({ where: { id: connectionId } });
    if (!connection || (connection.userAId !== userId && connection.userBId !== userId)) {
      this.logger.warn(`Socket ${client.id} (user ${userId}) tried to join connection ${connectionId} it isn't party to`);
      return false;
    }
    return true;
  }

  @SubscribeMessage('liveSnap:join')
  async handleJoin(@ConnectedSocket() client: Socket, @MessageBody() body: LiveSnapRoomPayload) {
    if (!(await this.verifyParty(client, body.connectionId))) return;

    const room = liveSnapRoom(body.connectionId);
    await client.join(room);
    client.data.liveSnapRoom = body;

    const members = this.server.sockets.adapter.rooms.get(room);
    const bothPresent = Boolean(members && members.size >= 2);
    if (!bothPresent) return; // first to join -- nothing to tell anyone yet

    await this.liveSnap.markActive(body.sessionId);
    // Exactly one side is told to create the WebRTC offer -- the second to
    // join, since it's the only moment both sockets are known to be ready.
    // Without this, both sides could independently decide to offer at
    // once (WebRTC "glare"), which this app has no renegotiation logic to
    // resolve.
    client.emit('liveSnap:peerJoined', { shouldOffer: true });
    client.to(room).emit('liveSnap:peerJoined', { shouldOffer: false });
  }

  // offer/answer/ice-candidate are pure relays -- never inspected, stored,
  // or validated beyond the room membership `join` already established.
  // `client.to(room)` (not `server.to(room)`) excludes the sender, which
  // is exactly "forward to the other peer" for a 2-person room.
  @SubscribeMessage('liveSnap:offer')
  handleOffer(@ConnectedSocket() client: Socket, @MessageBody() body: LiveSnapSignalPayload) {
    client.to(liveSnapRoom(body.connectionId)).emit('liveSnap:offer', body.payload);
  }

  @SubscribeMessage('liveSnap:answer')
  handleAnswer(@ConnectedSocket() client: Socket, @MessageBody() body: LiveSnapSignalPayload) {
    client.to(liveSnapRoom(body.connectionId)).emit('liveSnap:answer', body.payload);
  }

  @SubscribeMessage('liveSnap:ice-candidate')
  handleIceCandidate(@ConnectedSocket() client: Socket, @MessageBody() body: LiveSnapSignalPayload) {
    client.to(liveSnapRoom(body.connectionId)).emit('liveSnap:ice-candidate', body.payload);
  }

  @SubscribeMessage('liveSnap:leave')
  async handleLeave(@ConnectedSocket() client: Socket, @MessageBody() body: LiveSnapRoomPayload) {
    client.to(liveSnapRoom(body.connectionId)).emit('liveSnap:peerLeft');
    await client.leave(liveSnapRoom(body.connectionId));
    client.data.liveSnapRoom = undefined;
    await this.liveSnap.endSession(body.sessionId);
  }
}
