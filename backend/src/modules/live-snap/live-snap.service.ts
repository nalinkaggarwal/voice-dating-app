import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import type { LiveSnapSession } from '@prisma/client';
import { PrismaService } from '../../shared/prisma/prisma.service.js';
import { isBlocked } from '../../shared/moderation/block.util.js';
import { NotificationsService } from '../notifications/notifications.service.js';

@Injectable()
export class LiveSnapService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
  ) {}

  // startSession's own status check (MUTUAL_INTEREST/SNAP_PENDING only)
  // already excludes a BLOCKED connection, but checking the Block table
  // directly here too is the same defense-in-depth layer messaging's
  // getOwnedActiveConnection uses -- never rely on Connection.status alone
  // being the only thing standing between a blocked pair and a new call.
  private async getOwnedConnection(userId: string, connectionId: string) {
    const connection = await this.prisma.connection.findUnique({ where: { id: connectionId } });
    if (!connection) throw new NotFoundException('Connection not found');
    if (connection.userAId !== userId && connection.userBId !== userId) {
      throw new ForbiddenException('You are not a party to this connection');
    }
    const otherUserId = connection.userAId === userId ? connection.userBId : connection.userAId;
    if (await isBlocked(this.prisma, userId, otherUserId)) {
      throw new ForbiddenException('This connection is no longer available');
    }
    return connection;
  }

  // Starts (or resumes) a Live Snap call for this connection. SNAP_PENDING
  // is a valid starting point too -- it means a prior call already got one
  // side's confirmation; a dropped call can still be retried from there.
  // Returns the existing RINGING/ACTIVE session instead of creating a
  // second one if a call is already in flight (e.g. both parties hit
  // "start" independently).
  async startSession(userId: string, connectionId: string): Promise<LiveSnapSession> {
    const connection = await this.getOwnedConnection(userId, connectionId);
    if (connection.status !== 'MUTUAL_INTEREST' && connection.status !== 'SNAP_PENDING') {
      throw new ForbiddenException(`Cannot start Live Snap while status is ${connection.status}`);
    }

    const existing = await this.prisma.liveSnapSession.findFirst({
      where: { connectionId, status: { in: ['RINGING', 'ACTIVE'] } },
      orderBy: { startedAt: 'desc' },
    });
    if (existing) return existing;

    const session = await this.prisma.liveSnapSession.create({ data: { connectionId } });
    // WP7: ring the other party. Only on a genuinely new session -- the
    // early return above covers a re-tap on one already RINGING/ACTIVE --
    // so the callee is rung once per call, not once per tap.
    const calleeId = connection.userAId === userId ? connection.userBId : connection.userAId;
    await this.notifications.notifyLiveSnapInvite(calleeId, { connectionId, callerId: userId });
    return session;
  }

  // Latest session for this connection, for a client resuming after a
  // kill/reconnect to find out what state the call was last in -- same
  // "ask for the latest, don't require a remembered id" shape as
  // GET /ai-profile/voice/latest.
  async getSession(userId: string, connectionId: string): Promise<LiveSnapSession | null> {
    await this.getOwnedConnection(userId, connectionId);
    return this.prisma.liveSnapSession.findFirst({
      where: { connectionId },
      orderBy: { startedAt: 'desc' },
    });
  }

  // Called by the realtime gateway once both parties have joined the
  // signaling room for this session's connection.
  async markActive(sessionId: string): Promise<void> {
    await this.prisma.liveSnapSession.updateMany({
      where: { id: sessionId, status: 'RINGING' },
      data: { status: 'ACTIVE' },
    });
  }

  // Called by the realtime gateway on an explicit leave or a socket
  // disconnect. Guarded on still-RINGING/ACTIVE so this is a harmless
  // no-op if both parties leaving fires it twice for the same session.
  async endSession(sessionId: string): Promise<void> {
    await this.prisma.liveSnapSession.updateMany({
      where: { id: sessionId, status: { in: ['RINGING', 'ACTIVE'] } },
      data: { status: 'ENDED', endedAt: new Date() },
    });
  }
}
