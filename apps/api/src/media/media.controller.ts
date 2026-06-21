import {
  Body,
  Controller,
  Delete,
  Param,
  Post,
  Req,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Request } from 'express';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { PresignedUploadDto } from './dto/media.dto';
import { MediaService } from './media.service';

@ApiTags('media')
@ApiBearerAuth()
@Controller('media')
export class MediaController {
  constructor(private readonly mediaService: MediaService) {}

  @Post('presigned-upload')
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @ApiOperation({ summary: 'Get a presigned R2 URL for direct client upload' })
  presignedUpload(
    @CurrentUser() user: AuthUser,
    @Body() dto: PresignedUploadDto,
  ) {
    return this.mediaService.createPresignedUpload(user.id, dto);
  }

  /**
   * Right-to-erasure: deletes an R2 object owned by the calling user.
   * The :key is the R2 object key; we ensure the path contains the
   * caller's user_id segment before issuing the DeleteObjectCommand.
   * An admin (taxonomy_expert) can delete any key by passing X-Admin-Key.
   */
  @Delete('objects/:userId/:filename(*)')
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @ApiOperation({ summary: 'Delete a user-owned R2 object (right-to-erasure)' })
  deleteObject(
    @Param('userId') userId: string,
    @Param('filename') filename: string,
    @CurrentUser() user: AuthUser,
    @Req() req: Request,
    @AccessToken() _token: string,
  ) {
    const isAdmin = req.headers['x-admin-key'] === process.env['ADMIN_API_KEY'];
    return this.mediaService.deleteObject(userId, filename, user.id, isAdmin);
  }
}
