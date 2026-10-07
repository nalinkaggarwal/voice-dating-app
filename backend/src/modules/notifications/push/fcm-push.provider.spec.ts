import { ANDROID_CHANNEL_ID, FcmPushProvider } from './fcm-push.provider.js';

describe('FcmPushProvider', () => {
  const message = { title: 'T', body: 'B', data: { type: 'MUTUAL_MATCH', connectionId: 'c1' } };

  function sender(responses: Array<{ success: boolean; code?: string }>) {
    return {
      sendEachForMulticast: vi.fn(async (_payload: any) => ({
        successCount: responses.filter((r) => r.success).length,
        failureCount: responses.filter((r) => !r.success).length,
        responses: responses.map((r) =>
          r.success ? { success: true } : { success: false, error: { code: r.code } },
        ),
      })),
    };
  }

  it('sends one multicast with the Android channel the app creates, and maps per-token results', async () => {
    const messaging = sender([{ success: true }, { success: false, code: 'messaging/internal-error' }]);
    const provider = new FcmPushProvider(messaging as any);

    const results = await provider.sendToTokens(['tok-1', 'tok-2'], message);

    expect(messaging.sendEachForMulticast).toHaveBeenCalledTimes(1);
    const payload = messaging.sendEachForMulticast.mock.calls[0][0];
    expect(payload.tokens).toEqual(['tok-1', 'tok-2']);
    expect(payload.notification).toEqual({ title: 'T', body: 'B' });
    expect(payload.data).toEqual(message.data);
    expect(payload.android.notification.channelId).toBe(ANDROID_CHANNEL_ID);
    expect(results).toEqual([
      { token: 'tok-1', ok: true, unregistered: false },
      { token: 'tok-2', ok: false, unregistered: false, error: 'messaging/internal-error' },
    ]);
  });

  it('flags only FCM\'s dead-token codes as unregistered', async () => {
    const messaging = sender([
      { success: false, code: 'messaging/registration-token-not-registered' },
      { success: false, code: 'messaging/invalid-registration-token' },
      { success: false, code: 'messaging/quota-exceeded' },
    ]);
    const provider = new FcmPushProvider(messaging as any);

    const results = await provider.sendToTokens(['a', 'b', 'c'], message);
    expect(results.map((r) => r.unregistered)).toEqual([true, true, false]);
  });

  it('splits more than 500 tokens into multiple multicasts', async () => {
    const tokens = Array.from({ length: 1001 }, (_, i) => `tok-${i}`);
    const messaging = {
      sendEachForMulticast: vi.fn(async ({ tokens: batch }: any) => ({
        successCount: batch.length,
        failureCount: 0,
        responses: batch.map(() => ({ success: true })),
      })),
    };
    const provider = new FcmPushProvider(messaging as any);

    const results = await provider.sendToTokens(tokens, message);
    expect(messaging.sendEachForMulticast).toHaveBeenCalledTimes(3);
    expect(messaging.sendEachForMulticast.mock.calls.map((c: any) => c[0].tokens.length)).toEqual([500, 500, 1]);
    expect(results).toHaveLength(1001);
  });

  it('returns an empty list without calling FCM when there are no tokens', async () => {
    const messaging = sender([]);
    const provider = new FcmPushProvider(messaging as any);
    expect(await provider.sendToTokens([], message)).toEqual([]);
    expect(messaging.sendEachForMulticast).not.toHaveBeenCalled();
  });
});
