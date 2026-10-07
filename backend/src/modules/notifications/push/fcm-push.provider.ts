import { Logger } from '@nestjs/common';
import type { Messaging, MulticastMessage } from 'firebase-admin/messaging';
import type { PushMessage, PushProvider, PushSendResult } from './push-provider.interface.js';

// Must match the channel the mobile app creates in
// core/notifications/push_notifications.dart and declares as the default
// channel in AndroidManifest.xml -- Android 8+ drops notifications sent
// to a channel the app never created.
export const ANDROID_CHANNEL_ID = 'lolly_default';

// FCM's documented "this token will never work again" codes. Anything
// else (quota, transient 5xx, auth misconfiguration) is a failed send,
// not a dead token, and must NOT make us forget the device.
export const DEAD_TOKEN_ERROR_CODES: ReadonlySet<string> = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

// sendEachForMulticast accepts at most this many tokens per call.
const FCM_MULTICAST_LIMIT = 500;

// Only the one method we use, so tests can hand in a plain object and
// nothing here needs a real Firebase app to construct.
export type MulticastSender = Pick<Messaging, 'sendEachForMulticast'>;

export class FcmPushProvider implements PushProvider {
  private readonly logger = new Logger(FcmPushProvider.name);

  constructor(private readonly messaging: MulticastSender) {}

  async sendToTokens(tokens: string[], message: PushMessage): Promise<PushSendResult[]> {
    const results: PushSendResult[] = [];
    for (let start = 0; start < tokens.length; start += FCM_MULTICAST_LIMIT) {
      const batch = tokens.slice(start, start + FCM_MULTICAST_LIMIT);
      const payload: MulticastMessage = {
        tokens: batch,
        notification: { title: message.title, body: message.body },
        data: message.data,
        android: {
          priority: 'high',
          notification: { channelId: ANDROID_CHANNEL_ID },
        },
        apns: { payload: { aps: { sound: 'default' } } },
      };
      const response = await this.messaging.sendEachForMulticast(payload);
      response.responses.forEach((item, index) => {
        const token = batch[index];
        if (item.success) {
          results.push({ token, ok: true, unregistered: false });
          return;
        }
        const code = item.error?.code ?? 'unknown';
        const unregistered = DEAD_TOKEN_ERROR_CODES.has(code);
        if (!unregistered) {
          this.logger.warn(`FCM send failed for ${token.slice(0, 12)}...: ${code}`);
        }
        results.push({ token, ok: false, unregistered, error: code });
      });
    }
    return results;
  }
}
