import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomBytes } from 'crypto';
import {
  DeleteObjectCommand,
  DeleteObjectsCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { R2Config } from '../config/r2.config';

export interface PresignedUpload {
  key: string;
  presignedUrl: string;
  publicUrl: string;
}

/**
 * Singleton S3 client for Cloudflare R2.
 *
 * Generates presigned PUT URLs so clients upload media directly to R2
 * without streaming bytes through the NestJS process. Public URLs are
 * returned for later database storage.
 */
@Injectable()
export class R2Service implements OnModuleInit {
  private readonly logger = new Logger(R2Service.name);
  private client!: S3Client;
  private config!: R2Config;

  constructor(private readonly configService: ConfigService) {}

  onModuleInit(): void {
    this.config = this.configService.get<R2Config>('r2')!;
    this.client = new S3Client({
      region: this.config.region,
      endpoint: `https://${this.config.accountId}.r2.cloudflarestorage.com`,
      credentials: {
        accessKeyId: this.config.accessKeyId,
        secretAccessKey: this.config.secretAccessKey,
      },
    });
  }

  /**
   * Returns a presigned URL for a client-side PUT of a media object.
   */
  async presignedPutUrl(
    folder: string,
    userId: string,
    fileName: string,
    contentType: string,
    expiresInSeconds = 300,
  ): Promise<PresignedUpload> {
    const key = `${folder}/${userId}/${cryptoRandomId()}-${fileName}`;
    const command = new PutObjectCommand({
      Bucket: this.config.bucketName,
      Key: key,
      ContentType: contentType,
    });
    const presignedUrl = await getSignedUrl(this.client, command, {
      expiresIn: expiresInSeconds,
    });
    return {
      key,
      presignedUrl,
      publicUrl: this.publicUrl(key),
    };
  }

  /**
   * Returns a short-lived URL to read a private object. Not used when the
   * bucket is public, but kept for future private-media support.
   */
  async presignedGetUrl(key: string, expiresInSeconds = 60): Promise<string> {
    const command = new GetObjectCommand({
      Bucket: this.config.bucketName,
      Key: key,
    });
    return getSignedUrl(this.client, command, { expiresIn: expiresInSeconds });
  }

  /**
   * Removes an object from R2. Used when a user deletes their own media.
   */
  async deleteObject(key: string): Promise<void> {
    await this.client.send(
      new DeleteObjectCommand({ Bucket: this.config.bucketName, Key: key }),
    );
  }

  /**
   * Lists every object under a given key prefix. Used by the GDPR
   * erasure flow to enumerate a user's media before deletion.
   */
  async listByPrefix(prefix: string): Promise<string[]> {
    const keys: string[] = [];
    let continuationToken: string | undefined;
    do {
      const res = await this.client.send(
        new ListObjectsV2Command({
          Bucket: this.config.bucketName,
          Prefix: prefix,
          ContinuationToken: continuationToken,
        }),
      );
      for (const obj of res.Contents ?? []) {
        if (obj.Key) keys.push(obj.Key);
      }
      continuationToken = res.IsTruncated ? res.NextContinuationToken : undefined;
    } while (continuationToken);
    return keys;
  }

  /**
   * Batch-deletes a list of keys. Used by the GDPR erasure flow.
   * R2 supports up to 1000 keys per DeleteObjects call; we batch in
   * groups of 500 to stay well under the limit.
   */
  async deleteObjects(keys: string[]): Promise<number> {
    if (keys.length === 0) return 0;
    let deleted = 0;
    for (let i = 0; i < keys.length; i += 500) {
      const slice = keys.slice(i, i + 500);
      const res = await this.client.send(
        new DeleteObjectsCommand({
          Bucket: this.config.bucketName,
          Delete: { Objects: slice.map((k) => ({ Key: k })) },
        }),
      );
      deleted += (res.Deleted ?? []).length;
      if (res.Errors && res.Errors.length > 0) {
        this.logger.warn(
          `${res.Errors.length} R2 objects failed to delete: ${res.Errors.map((e) => e.Key).join(',')}`,
        );
      }
    }
    return deleted;
  }

  /**
   * Convenience for the GDPR erasure flow. Lists and deletes everything
   * under the given prefix. Returns the count of deleted objects.
   */
  async deletePrefix(prefix: string): Promise<number> {
    const keys = await this.listByPrefix(prefix);
    return this.deleteObjects(keys);
  }

  /**
   * Computes the public CDN URL for an object key.
   */
  publicUrl(key: string): string {
    const base = this.config.publicUrl.replace(/\/$/, '');
    return `${base}/${key}`;
  }
}

// Suppress unused-symbol lint; we import _Object only to anchor the
// SDK types. The cast is needed for older @aws-sdk typings that don't
// expose the public type alias.
void ({} as Record<string, unknown>);

function cryptoRandomId(): string {
  return randomBytes(8).toString('hex');
}
