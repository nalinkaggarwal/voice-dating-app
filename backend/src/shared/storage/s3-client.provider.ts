import { S3Client } from '@aws-sdk/client-s3';
import { ConfigService } from '@nestjs/config';
import type { Provider } from '@nestjs/common';

export const S3_CLIENT = 'S3_CLIENT';

// S3-compatible client (works against real S3 or a local MinIO via
// S3_ENDPOINT/S3_FORCE_PATH_STYLE) -- injected wherever a future upload
// flow needs it. Kept as a plain factory, not a service class, since
// there's no behavior to wrap yet.
export const s3ClientFactory: Provider = {
  provide: S3_CLIENT,
  inject: [ConfigService],
  useFactory: (config: ConfigService) =>
    new S3Client({
      region: config.get<string>('S3_REGION', 'us-east-1'),
      endpoint: config.get<string>('S3_ENDPOINT'),
      forcePathStyle: config.get<string>('S3_FORCE_PATH_STYLE') === 'true',
      credentials: {
        accessKeyId: config.get<string>('S3_ACCESS_KEY_ID', ''),
        secretAccessKey: config.get<string>('S3_SECRET_ACCESS_KEY', ''),
      },
    }),
};
