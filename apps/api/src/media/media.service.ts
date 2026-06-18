import { Injectable, ForbiddenException } from '@nestjs/common';
import { R2Service, PresignedUpload } from '../storage/r2.service';
import { PresignedUploadDto } from './dto/media.dto';

@Injectable()
export class MediaService {
  constructor(private readonly r2: R2Service) {}

  async createPresignedUpload(
    userId: string,
    dto: PresignedUploadDto,
  ): Promise<PresignedUpload> {
    // Sanitize file_name (H-7). Only allow safe characters; reject empty
    // results. The previous implementation concatenated the raw user
    // input into the R2 key, allowing path traversal in the URL.
    const safeName = dto.file_name
      .replace(/[^A-Za-z0-9._-]/g, '_')
      .slice(0, 200);
    if (!safeName) {
      throw new ForbiddenException('Invalid file name');
    }

    return this.r2.presignedPutUrl(
      dto.folder,
      userId,
      safeName,
      dto.content_type,
      dto.expires_in ?? 300,
    );
  }

  /**
   * Right-to-erasure (DD-2.18). Deletes an R2 object, but only after
   * verifying the key path begins with the calling user's user_id
   * (or the caller is an admin).
   */
  async deleteObject(
    userId: string,
    filename: string,
    callerUserId: string,
    isAdmin: boolean,
  ): Promise<{ deleted: true; key: string }> {
    if (!isAdmin && userId !== callerUserId) {
      throw new ForbiddenException('You may only delete your own R2 objects');
    }
    // Re-sanitize the filename to construct the same key the uploader
    // would have produced. Filenames come from R2 keys we previously
    // issued, so they should already be sanitized — we re-sanitize
    // defensively.
    const safeName = filename.replace(/[^A-Za-z0-9._/-]/g, '_');
    const key = `sightings/${userId}/${safeName}`;
    await this.r2.deleteObject(key);
    return { deleted: true, key };
  }
}
