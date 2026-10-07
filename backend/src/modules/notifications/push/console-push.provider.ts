import { Injectable, Logger } from '@nestjs/common';
import type { PushMessage, PushProvider, PushSendResult } from './push-provider.interface.js';

// Dev stub: logs what WOULD have been pushed instead of delivering it.
// Selected automatically when FIREBASE_SERVICE_ACCOUNT_PATH/JSON is unset
// (see push-provider.factory.ts), so a fresh clone runs without Firebase
// and the hook points in messaging/connections/live-snap are still
// visibly exercised in the server log.
@Injectable()
export class ConsolePushProvider implements PushProvider {
  private readonly logger = new Logger(ConsolePushProvider.name);

  async sendToTokens(tokens: string[], message: PushMessage): Promise<PushSendResult[]> {
    for (const token of tokens) {
      this.logger.log(
        `[DEV PUSH] -> ${token.slice(0, 12)}... | ${message.title} | ${message.body} | ${JSON.stringify(message.data)}`,
      );
    }
    return tokens.map((token) => ({ token, ok: true, unregistered: false }));
  }
}
