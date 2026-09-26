import { Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { GetObjectCommand, PutObjectCommand, type S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { S3_CLIENT } from './s3-client.provider.js';

const UPLOAD_URL_TTL_SECONDS = 300; // 5 minutes to complete the direct upload
const DOWNLOAD_URL_TTL_SECONDS = 900; // 15 minutes to view a private asset

/**
 * All signed-URL generation for direct-to-S3 uploads lives here -- the
 * API never proxies file bytes through itself (audio/photos can be
 * large; a signed PUT lets the client upload straight to storage).
 *
 * WP2 scope: voice recordings and profile photos. Both use the SAME
 * pattern (get a signed PUT URL for a fresh key, client uploads, client
 * tells the backend the key once done) -- profile/ai-profile services
 * call this, never touch S3Client directly.
 */
@Injectable()
export class StorageService {
  private readonly bucket: string;

  constructor(
    @Inject(S3_CLIENT) private readonly s3: S3Client,
    private readonly config: ConfigService,
  ) {
    this.bucket = this.config.get<string>('S3_BUCKET', 'lolly-dev');
  }

  /** e.g. generateKey('voice', 'webm') -> "voice/2f1e...-c9.webm" */
  generateKey(prefix: string, extension: string): string {
    return `${prefix}/${randomUUID()}.${extension}`;
  }

  async getUploadUrl(key: string, contentType: string): Promise<string> {
    const command = new PutObjectCommand({ Bucket: this.bucket, Key: key, ContentType: contentType });
    return getSignedUrl(this.s3, command, { expiresIn: UPLOAD_URL_TTL_SECONDS });
  }

  async getDownloadUrl(key: string): Promise<string> {
    const command = new GetObjectCommand({ Bucket: this.bucket, Key: key });
    return getSignedUrl(this.s3, command, { expiresIn: DOWNLOAD_URL_TTL_SECONDS });
  }
}
