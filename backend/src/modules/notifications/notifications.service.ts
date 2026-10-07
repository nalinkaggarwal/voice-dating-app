import { Inject, Injectable, Logger } from '@nestjs/common';
import type { DevicePlatform, DeviceToken, MessageType } from '@prisma/client';
import { PrismaService } from '../../shared/prisma/prisma.service.js';
import { PUSH_PROVIDER, type PushMessage, type PushProvider } from './push/push-provider.interface.js';

// The `type` value every push carries in its data payload. The mobile
// client switches on this (core/notifications/push_payload.dart) to decide
// where a tap lands; keep the two lists in sync.
export type PushKind = 'NEW_MESSAGE' | 'MUTUAL_MATCH' | 'LIVE_SNAP_INVITE' | 'AUTHENTICATED_MATCH';

export interface PushDeliverySummary {
  requested: number;
  delivered: number;
  failed: number;
  // Tokens FCM declared dead and we deleted as a result.
  forgotten: number;
}

const NO_DEVICES: PushDeliverySummary = { requested: 0, delivered: 0, failed: 0, forgotten: 0 };
const MESSAGE_PREVIEW_MAX_CHARS = 80;
// Used wherever a display name is allowed but the sender simply hasn't
// set one -- never as a way to hide identity (that's the MUTUAL_MATCH
// case below, which deliberately looks nothing up).
const FALLBACK_DISPLAY_NAME = 'Your match';

/**
 * WP7: push notifications. Two responsibilities:
 *  1. Device-token bookkeeping (register on login, unregister on logout,
 *     forget tokens FCM reports as dead).
 *  2. One typed `notifyX` method per product event, each owning the exact
 *     wording and -- more importantly -- what identity it is allowed to
 *     leak. "Hear before you see" applies to pushes too: a MUTUAL_MATCH
 *     push carries no name, because the Reveal step hasn't happened yet
 *     (ConnectionsService.getReveal gates on MUTUAL_INTEREST, so from that
 *     status on a name is fair game, which is why Live Snap invites and
 *     match confirmations do include one).
 *
 * Every notifyX resolves to a delivery summary and NEVER throws: a push
 * failing must not fail the message/match/call that triggered it. The
 * triggering services await these calls only so tests are deterministic.
 */
@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    @Inject(PUSH_PROVIDER) private readonly push: PushProvider,
  ) {}

  // Upsert keyed on the token, not the user -- see DeviceToken's schema
  // comment. A token already on file for another account is reassigned.
  async registerDevice(userId: string, token: string, platform: DevicePlatform): Promise<DeviceToken> {
    return this.prisma.deviceToken.upsert({
      where: { token },
      create: { userId, token, platform },
      update: { userId, platform },
    });
  }

  // Scoped to the caller's own tokens so one user can't unregister
  // another's device by guessing (or leaking) a token value.
  async unregisterDevice(userId: string, token: string): Promise<{ removed: number }> {
    const { count } = await this.prisma.deviceToken.deleteMany({ where: { token, userId } });
    return { removed: count };
  }

  async notifyNewMessage(
    recipientId: string,
    input: { connectionId: string; senderId: string; type: MessageType; textContent: string | null },
  ): Promise<PushDeliverySummary> {
    const senderName = await this.displayNameOf(input.senderId);
    const body =
      input.type === 'VOICE'
        ? `${senderName} sent you a voice message`
        : truncate(input.textContent ?? '', MESSAGE_PREVIEW_MAX_CHARS);
    return this.sendToUser(recipientId, {
      title: senderName,
      body,
      data: {
        type: 'NEW_MESSAGE' satisfies PushKind,
        connectionId: input.connectionId,
        otherUserId: input.senderId,
        otherDisplayName: senderName,
      },
    });
  }

  // Deliberately anonymous: no name, no photo, no profile lookup at all.
  // The recipient finds out WHO by opening the app and going through
  // Mutual Reveal, same as they would without a push.
  async notifyMutualMatch(
    recipientId: string,
    input: { connectionId: string; otherUserId: string },
  ): Promise<PushDeliverySummary> {
    return this.sendToUser(recipientId, {
      title: "It's a mutual match",
      body: 'Someone you liked likes you back. Open Lolly to hear them.',
      data: {
        type: 'MUTUAL_MATCH' satisfies PushKind,
        connectionId: input.connectionId,
        otherUserId: input.otherUserId,
      },
    });
  }

  async notifyLiveSnapInvite(
    recipientId: string,
    input: { connectionId: string; callerId: string },
  ): Promise<PushDeliverySummary> {
    const callerName = await this.displayNameOf(input.callerId);
    return this.sendToUser(recipientId, {
      title: `${callerName} wants to Live Snap`,
      body: 'Join now to see each other live before you both decide.',
      data: {
        type: 'LIVE_SNAP_INVITE' satisfies PushKind,
        connectionId: input.connectionId,
        otherUserId: input.callerId,
        otherDisplayName: callerName,
      },
    });
  }

  async notifyAuthenticatedMatch(
    recipientId: string,
    input: { connectionId: string; otherUserId: string },
  ): Promise<PushDeliverySummary> {
    const otherName = await this.displayNameOf(input.otherUserId);
    return this.sendToUser(recipientId, {
      title: "You're matched",
      body: `${otherName} confirmed too. Your chat is open.`,
      data: {
        type: 'AUTHENTICATED_MATCH' satisfies PushKind,
        connectionId: input.connectionId,
        otherUserId: input.otherUserId,
        otherDisplayName: otherName,
      },
    });
  }

  // The single delivery path. Never throws (see class docstring); a
  // provider blowing up is logged and reported as all-failed.
  private async sendToUser(userId: string, message: PushMessage): Promise<PushDeliverySummary> {
    const devices = await this.prisma.deviceToken.findMany({ where: { userId } });
    if (devices.length === 0) {
      this.logger.debug(`No device tokens for user ${userId}; skipping push "${message.title}"`);
      return NO_DEVICES;
    }

    const tokens = devices.map((d) => d.token);
    let results;
    try {
      results = await this.push.sendToTokens(tokens, message);
    } catch (err) {
      this.logger.error(`Push provider failed for user ${userId}: ${(err as Error).message}`);
      return { requested: tokens.length, delivered: 0, failed: tokens.length, forgotten: 0 };
    }

    const dead = results.filter((r) => r.unregistered).map((r) => r.token);
    if (dead.length > 0) {
      await this.prisma.deviceToken.deleteMany({ where: { token: { in: dead } } });
      this.logger.log(`Forgot ${dead.length} dead device token(s) for user ${userId}`);
    }

    return {
      requested: tokens.length,
      delivered: results.filter((r) => r.ok).length,
      failed: results.filter((r) => !r.ok).length,
      forgotten: dead.length,
    };
  }

  private async displayNameOf(userId: string): Promise<string> {
    const profile = await this.prisma.profile.findUnique({ where: { userId } });
    const name = profile?.displayName?.trim();
    return name ? name : FALLBACK_DISPLAY_NAME;
  }
}

function truncate(text: string, max: number): string {
  const single = text.replace(/\s+/g, ' ').trim();
  return single.length <= max ? single : `${single.slice(0, max - 1)}…`;
}
