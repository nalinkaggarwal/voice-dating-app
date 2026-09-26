import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { S3_CLIENT, s3ClientFactory } from './s3-client.provider.js';

// WP1 scope: wire up the client only. No upload/download flows yet --
// those land with profile photo + voice clip handling in a later WP.
@Module({
  imports: [ConfigModule],
  providers: [s3ClientFactory],
  exports: [S3_CLIENT],
})
export class StorageModule {}
