import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Req,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Request } from 'express';
import { Public } from '../common/decorators/public.decorator';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { RequiresTaxonomyExpert } from '../common/decorators/taxonomy-expert.decorator';
import { TaxonomyExpertGuard } from '../common/guards/taxonomy-expert.guard';
import { AuthUser } from '../common/types/auth-user.interface';
import {
  CreateSightingDto,
  ListSightingsDto,
  UpdateSightingDto,
} from './dto/sighting.dto';
import { SightingsService } from './sightings.service';

function optionalToken(req: Request): string | undefined {
  const auth = req.headers.authorization;
  return auth?.startsWith('Bearer ') ? auth.slice(7).trim() : undefined;
}

@ApiTags('sightings')
@Controller('sightings')
export class SightingsController {
  constructor(private readonly sightingsService: SightingsService) {}

  @Public()
  @Get()
  @ApiOperation({ summary: 'Public sightings feed' })
  list(@Query() query: ListSightingsDto, @Req() req: Request) {
    return this.sightingsService.list(optionalToken(req), query);
  }

  /**
   * Darwin Core export is exposed via the Edge Function (gated by a
   * shared secret and a CRON schedule), NOT the API. The previous public
   * service-role route is removed because anyone could scrape the entire
   * verified dataset (PII + GBIF-eligible records) and there was no rate
   * limit. The Edge Function is at /functions/v1/darwin-core-export.
   */
  // (intentionally no public export route here)

  @Public()
  @Get(':id')
  @ApiOperation({ summary: 'Get sighting detail' })
  getById(@Param('id') id: string, @Req() req: Request) {
    return this.sightingsService.getById(optionalToken(req), id);
  }

  @Post()
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Create a sighting' })
  create(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: CreateSightingDto,
  ) {
    return this.sightingsService.create(token, user.id, dto);
  }

  @Patch(':id')
  @ApiBearerAuth()
  update(
    @AccessToken() token: string,
    @CurrentUser() user: AuthUser,
    @Param('id') id: string,
    @Body() dto: UpdateSightingDto,
  ) {
    return this.sightingsService.update(token, user.id, id, dto);
  }

  @Delete(':id')
  @ApiBearerAuth()
  remove(
    @AccessToken() token: string,
    @CurrentUser() user: AuthUser,
    @Param('id') id: string,
    @Query('reason') reason?: string,
  ) {
    return this.sightingsService.remove(token, user.id, id, reason);
  }

  /**
   * Verify a sighting. ONLY callable by users with users.taxonomy_expert = true.
   * Self-verification is rejected (the calling user must not be the
   * sighting's reporter).
   */
  @Post(':id/verify')
  @ApiBearerAuth()
  @UseGuards(TaxonomyExpertGuard)
  @RequiresTaxonomyExpert()
  @ApiOperation({ summary: 'Verify a sighting (taxonomy expert only)' })
  verify(
    @AccessToken() token: string,
    @CurrentUser() user: AuthUser,
    @Param('id') id: string,
  ) {
    return this.sightingsService.verify(token, user.id, id);
  }
}
