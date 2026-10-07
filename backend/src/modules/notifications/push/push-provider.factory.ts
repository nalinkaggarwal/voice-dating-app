import { readFileSync } from 'node:fs';
import { Logger } from '@nestjs/common';
import type { ConfigService } from '@nestjs/config';
import { cert, getApps, initializeApp, type ServiceAccount } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { ConsolePushProvider } from './console-push.provider.js';
import { FcmPushProvider } from './fcm-push.provider.js';
import type { PushProvider } from './push-provider.interface.js';

const logger = new Logger('PushProviderFactory');

// Picks the push implementation from config, once, at module init:
// - FIREBASE_SERVICE_ACCOUNT_JSON: the service-account JSON inline (for
//   hosted environments that inject secrets as env vars), else
// - FIREBASE_SERVICE_ACCOUNT_PATH: path to the downloaded key file, else
// - neither: ConsolePushProvider, with a loud warning so nobody mistakes
//   a logged push for a delivered one.
export function buildPushProvider(config: ConfigService): PushProvider {
  const inlineJson = config.get<string>('FIREBASE_SERVICE_ACCOUNT_JSON');
  const path = config.get<string>('FIREBASE_SERVICE_ACCOUNT_PATH');

  if (!inlineJson && !path) {
    logger.warn(
      'FIREBASE_SERVICE_ACCOUNT_PATH / FIREBASE_SERVICE_ACCOUNT_JSON not set -- ' +
        'push notifications will be LOGGED, not delivered (ConsolePushProvider).',
    );
    return new ConsolePushProvider();
  }

  const serviceAccount = JSON.parse(inlineJson ?? readFileSync(path!, 'utf8')) as ServiceAccount;
  // firebase-admin keeps a process-wide app registry; re-using an existing
  // default app keeps hot-reload (nest start --watch) from throwing
  // "app already exists".
  const app = getApps()[0] ?? initializeApp({ credential: cert(serviceAccount) });
  logger.log(`Push notifications via FCM, project ${serviceAccount.projectId ?? '(unknown)'}`);
  return new FcmPushProvider(getMessaging(app));
}
