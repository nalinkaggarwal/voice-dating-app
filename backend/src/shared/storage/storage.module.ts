import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { S3_CLIENT, s3ClientFactory } from './s3-client.provider.js';
import { StorageService } from './storage.service.js';

@Module({
  imports: [ConfigModule],
  providers: [s3ClientFactory, StorageService],
  exports: [S3_CLIENT, StorageService],
})
export class StorageModule {}
