// The one seam between "the app decided to notify someone" and "a real
// push went out". FcmPushProvider is the production implementation;
// ConsolePushProvider is the dev stub (same shape as identity's
// ConsoleOtpProvider) that NotificationsModule falls back to when no
// Firebase service account is configured.

export interface PushMessage {
  title: string;
  body: string;
  // FCM data payloads must be flat string -> string maps; the mobile
  // client parses these in core/notifications/push_payload.dart.
  data: Record<string, string>;
}

export interface PushSendResult {
  token: string;
  ok: boolean;
  // True when the provider says this token is permanently dead
  // (app uninstalled, token rotated) and the caller should forget it.
  unregistered: boolean;
  error?: string;
}

export interface PushProvider {
  sendToTokens(tokens: string[], message: PushMessage): Promise<PushSendResult[]>;
}

export const PUSH_PROVIDER = 'PUSH_PROVIDER';
