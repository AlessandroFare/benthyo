import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Public } from '../common/decorators/public.decorator';
import { AccessToken, CurrentUser } from '../common/decorators/current-user.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { IdentifySpeciesDto, ListSpeciesDto, SetEmbeddingDto, SimilarSpeciesQueryDto } from './dto/species.dto';
import { SpeciesService } from './species.service';

@ApiTags('species')
@Controller('species')
export class SpeciesController {
  constructor(private readonly speciesService: SpeciesService) {}

  @Public()
  @Get()
  @ApiOperation({ summary: 'List species with optional filters and full-text search' })
  list(@AccessToken() token: string | undefined, @Query() query: ListSpeciesDto) {
    return this.speciesService.list(token, query);
  }

  @Public()
  @Get('similar')
  @ApiOperation({
    summary: 'Approximate-NN species search using pgvector (HNSW index)',
  })
  findSimilar(
    @AccessToken() token: string | undefined,
    @Query() query: SimilarSpeciesQueryDto,
  ) {
    return this.speciesService.findSimilar(token, query);
  }

  @Public()
  @Get(':id')
  @ApiOperation({ summary: 'Get species detail with top sites' })
  async getById(@AccessToken() token: string | undefined, @Param('id') id: string) {
    const [species, sites] = await Promise.all([
      this.speciesService.getById(token, id),
      this.speciesService.getTopSites(token, id),
    ]);
    return { ...species, top_sites: sites.slice(0, 10) };
  }

  @Public()
  @Get(':id/sightings')
  @ApiOperation({ summary: 'Recent sightings of a species' })
  getSightings(
    @AccessToken() token: string | undefined,
    @Param('id') id: string,
    @Query() query: ListSpeciesDto,
  ) {
    return this.speciesService.getSightings(token, id, query);
  }

  @Post('identify')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Proxy to iNaturalist for species identification from image URL' })
  identify(@Body() dto: IdentifySpeciesDto) {
    return this.speciesService.identify(dto);
  }

  /**
   * Upload a 384-dim embedding for a species. Computed on-device by the
   * Flutter app (TFLite all-MiniLM-L6-v2). Persists via the SECURITY
   * DEFINER RPC from migration 032 and writes an audit row.
   */
  @Post(':id/embedding')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Upload a 384-dim semantic embedding for a species' })
  setEmbedding(
    @AccessToken() token: string,
    @CurrentUser() user: AuthUser,
    @Param('id') id: string,
    @Body() dto: SetEmbeddingDto,
  ) {
    return this.speciesService.setEmbedding(token, user, id, dto);
  }
}
