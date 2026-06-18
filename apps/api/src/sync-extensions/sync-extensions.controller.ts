import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Public } from '../common/decorators/public.decorator';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { SyncExtensionsService } from './sync-extensions.service';

@ApiTags('sync')
@Controller()
export class SyncExtensionsController {
  constructor(private readonly sync: SyncExtensionsService) {}

  @Post('sightings/:id/push-inaturalist')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Queue verified sighting for iNaturalist push' })
  pushInat(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id') id: string,
  ) {
    return this.sync.queueInatPush(token, user.id, id);
  }

  @Post('users/me/gbif-export')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Mark verified sightings for GBIF export batch' })
  pushGbif(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.sync.pushGbifExport(token, user.id);
  }

  @Post('sightings/photo-fingerprint')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Register photo SHA256 for reverse search' })
  fingerprint(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body()
    dto: { sighting_id: string; photo_url: string; sha256: string; species_id?: string },
  ) {
    return this.sync.registerPhotoFingerprint(token, user.id, dto);
  }

  @Public()
  @Get('sightings/photo-search')
  @ApiOperation({ summary: 'Find sightings by photo hash (reverse search)' })
  photoSearch(@Query('hash') hash: string, @Query('user_id') userId?: string) {
    return this.sync.searchByPhotoHash(hash, userId);
  }

  @Post('sightings/photo-embedding')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Register CLIP embedding (512-d) for vector search' })
  clipEmbedding(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body()
    dto: {
      sighting_id: string;
      photo_url: string;
      sha256: string;
      embedding: number[];
      species_id?: string;
    },
  ) {
    return this.sync.registerClipEmbedding(token, user.id, dto);
  }

  @Public()
  @Post('sightings/vector-search')
  @ApiOperation({ summary: 'Find similar sightings by CLIP embedding' })
  vectorSearch(
    @Body() body: { embedding: number[]; limit?: number },
  ) {
    return this.sync.searchByClipEmbedding(body.embedding, body.limit ?? 10);
  }
}
