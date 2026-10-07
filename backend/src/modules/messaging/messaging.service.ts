import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import type { Message } from '@prisma/client';
import { MessageType } from '@prisma/client';
import { PrismaService } from '../../shared/prisma/prisma.service.js';
import { StorageService } from '../../shared/storage/storage.service.js';
import { audioExtensionForContentType } from '../../shared/storage/audio-extension.util.js';
import { isBlocked } from '../../shared/moderation/block.util.js';
import { RealtimeGateway } from '../realtime/realtime.gateway.js';
import type { SendMessageDto } from './dto/send-message.dto.js';

export interface ConversationSummary {
  connectionId: string;
  // The OTHER party's id -- needed so the client can address a
  // block()/report() call against them from the thread screen; safe to
  // expose here since this is already an AUTHENTICATED_MATCH/ACTIVE
  // connection with full identity revealed.
  otherUserId: string;
  displayName: string | null;
  photoUrl: string | null;
  lastMessage: { type: MessageType; textContent: string | null; sentAt: Date } | null;
}

const DEFAULT_PAGE_SIZE = 30;
const MAX_PAGE_SIZE = 100;

@Injectable()
export class MessagingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    private readonly gateway: RealtimeGateway,
  ) {}

  // The one access-control gate every method below goes through: caller
  // must be a party to the connection, AND it must be AUTHENTICATED_MATCH
  // or ACTIVE. This is an ALLOWLIST, not a denylist -- SUGGESTED,
  // MUTUAL_INTEREST, SNAP_PENDING, CLOSED, and BLOCKED are all rejected by
  // not being in the allowed set, so ConnectionsService.block() setting
  // status to BLOCKED already cuts messaging off for free. The isBlocked
  // check below is the defense-in-depth layer on top of that -- it hits
  // the Block table directly rather than trusting Connection.status alone,
  // so a block is still enforced even in the (currently impossible, but
  // not provably so forever) case that status drifted out of sync.
  private async getOwnedActiveConnection(userId: string, connectionId: string) {
    const connection = await this.prisma.connection.findUnique({ where: { id: connectionId } });
    if (!connection) throw new NotFoundException('Connection not found');
    if (connection.userAId !== userId && connection.userBId !== userId) {
      throw new ForbiddenException('You are not a party to this connection');
    }
    if (connection.status !== 'AUTHENTICATED_MATCH' && connection.status !== 'ACTIVE') {
      throw new ForbiddenException(`Cannot message while connection status is ${connection.status}`);
    }
    const otherUserId = connection.userAId === userId ? connection.userBId : connection.userAId;
    if (await isBlocked(this.prisma, userId, otherUserId)) {
      throw new ForbiddenException('This connection is no longer available');
    }
    return connection;
  }

  async requestVoiceUploadUrl(contentType: string): Promise<{ uploadUrl: string; key: string }> {
    const extension = audioExtensionForContentType(contentType);
    const key = this.storage.generateKey('message-voice', extension);
    const uploadUrl = await this.storage.getUploadUrl(key, contentType);
    return { uploadUrl, key };
  }

  // No ValidationPipe is registered anywhere in this app (see the dto's
  // own note), so SendMessageDto's decorators don't actually run -- this
  // is the real enforcement for the type-specific required fields.
  private validateSendDto(dto: SendMessageDto): void {
    if (dto.type === MessageType.TEXT && !dto.textContent?.trim()) {
      throw new BadRequestException('textContent is required for a TEXT message');
    }
    if (dto.type === MessageType.VOICE) {
      if (!dto.audioUrl) throw new BadRequestException('audioUrl is required for a VOICE message');
      if (!dto.audioDurationSec || dto.audioDurationSec < 1 || dto.audioDurationSec > 60) {
        throw new BadRequestException('audioDurationSec must be between 1 and 60 (inclusive)');
      }
    }
  }

  // Sending is REST-only -- consistent with every other business action
  // in this app (Live Snap's start/confirm/decline included). Sockets
  // never create data, only broadcast that this call already did.
  async sendMessage(userId: string, connectionId: string, dto: SendMessageDto): Promise<Message> {
    const connection = await this.getOwnedActiveConnection(userId, connectionId);
    this.validateSendDto(dto);

    const message = await this.prisma.message.create({
      data: {
        connectionId,
        senderId: userId,
        type: dto.type,
        textContent: dto.type === MessageType.TEXT ? dto.textContent : null,
        audioUrl: dto.type === MessageType.VOICE ? dto.audioUrl : null,
        audioDurationSec: dto.type === MessageType.VOICE ? dto.audioDurationSec : null,
      },
    });

    if (connection.status === 'AUTHENTICATED_MATCH') {
      // The first message in a match starts the "active conversation" --
      // guarded so every later message in the same connection is a
      // harmless no-op here, same guarded-updateMany idiom as decline()
      // and advance-status.util.ts.
      await this.prisma.connection.updateMany({
        where: { id: connectionId, status: 'AUTHENTICATED_MATCH' },
        data: { status: 'ACTIVE' },
      });
    }

    this.gateway.broadcastToChat(connectionId, 'message:new', message);
    return message;
  }

  // `before` (exclusive) pages backward through history, newest page
  // first but returned in chronological order. `since` (exclusive) is the
  // reconnect-catch-up path -- everything newer than the last message the
  // client already has, no pagination (a realistic gap is never large
  // enough to need it). Passing both is treated as `since` taking
  // priority; a client only ever needs one or the other at a time.
  async getHistory(
    userId: string,
    connectionId: string,
    options: { before?: string; since?: string; limit?: number },
  ): Promise<{ messages: Message[]; hasMore: boolean }> {
    await this.getOwnedActiveConnection(userId, connectionId);

    if (options.since) {
      const messages = await this.prisma.message.findMany({
        where: { connectionId, sentAt: { gt: new Date(options.since) } },
        orderBy: { sentAt: 'asc' },
      });
      return { messages, hasMore: false };
    }

    const limit = Math.min(options.limit ?? DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE);
    const rows = await this.prisma.message.findMany({
      where: { connectionId, ...(options.before ? { sentAt: { lt: new Date(options.before) } } : {}) },
      orderBy: { sentAt: 'desc' },
      take: limit + 1,
    });
    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;
    return { messages: page.reverse(), hasMore };
  }

  async markDelivered(userId: string, connectionId: string): Promise<{ upTo: Date }> {
    await this.getOwnedActiveConnection(userId, connectionId);
    const upTo = new Date();
    await this.prisma.message.updateMany({
      where: { connectionId, senderId: { not: userId }, deliveredAt: null, sentAt: { lte: upTo } },
      data: { deliveredAt: upTo },
    });
    this.gateway.broadcastToChat(connectionId, 'message:delivered', { connectionId, upTo });
    return { upTo };
  }

  // Implies delivered -- a message can't be read without having arrived.
  // Two guarded updateMany calls rather than one so a message delivered
  // earlier keeps ITS real deliveredAt instead of being overwritten with
  // the (later) read timestamp.
  async markRead(userId: string, connectionId: string): Promise<{ upTo: Date }> {
    await this.getOwnedActiveConnection(userId, connectionId);
    const upTo = new Date();
    const base = { connectionId, senderId: { not: userId }, sentAt: { lte: upTo } };
    await this.prisma.message.updateMany({ where: { ...base, deliveredAt: null }, data: { deliveredAt: upTo } });
    await this.prisma.message.updateMany({ where: { ...base, readAt: null }, data: { readAt: upTo } });
    this.gateway.broadcastToChat(connectionId, 'message:read', { connectionId, upTo });
    return { upTo };
  }

  // One conversation per AUTHENTICATED_MATCH/ACTIVE Connection this user
  // is party to -- WP3's one-candidate-a-day limit caps how fast NEW
  // matches appear, not how many stay active at once, so there can
  // legitimately be more than one.
  async listConversations(userId: string): Promise<ConversationSummary[]> {
    const connections = await this.prisma.connection.findMany({
      where: { status: { in: ['AUTHENTICATED_MATCH', 'ACTIVE'] }, OR: [{ userAId: userId }, { userBId: userId }] },
      orderBy: { updatedAt: 'desc' },
    });

    return Promise.all(
      connections.map(async (connection) => {
        const otherUserId = connection.userAId === userId ? connection.userBId : connection.userAId;
        const [profile, lastMessage] = await Promise.all([
          this.prisma.profile.findUnique({ where: { userId: otherUserId } }),
          this.prisma.message.findFirst({ where: { connectionId: connection.id }, orderBy: { sentAt: 'desc' } }),
        ]);
        const photoUrl = profile?.photoUrl ? await this.storage.getDownloadUrl(profile.photoUrl) : null;
        return {
          connectionId: connection.id,
          otherUserId,
          displayName: profile?.displayName ?? null,
          photoUrl,
          lastMessage: lastMessage
            ? { type: lastMessage.type, textContent: lastMessage.textContent, sentAt: lastMessage.sentAt }
            : null,
        };
      }),
    );
  }
}
