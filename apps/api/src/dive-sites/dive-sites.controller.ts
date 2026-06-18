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
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Request } from 'express';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { Public } from '../common/decorators/public.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import {
  CreateDiveSiteDto,
  ListDiveSitesDto,
  ListSiteSightingsDto,
  NearbyDiveSitesDto,
  SearchDiveSitesDto,
  UpdateDiveSiteDto,
} from './dto/dive-site.dto';
import { DiveSitesService } from './dive-sites.service';

function optionalToken(req: Request): string | undefined {
  const auth = req.headers.authorization;
  return auth?.startsWith('Bearer ') ? auth.slice(7).trim() : undefined;
}

@ApiTags('dive-sites')
@Controller('dive-sites')
export class DiveSitesController {
  constructor(private readonly diveSitesService: DiveSitesService) {}

  @Public()
  @Get()
  @ApiOperation({ summary: 'List dive sites with optional filters' })
  list(@Query() query: ListDiveSitesDto, @Req() req: Request) {
    return this.diveSitesService.list(optionalToken(req), query);
  }

  @Public()
  @Get('nearby')
  @ApiOperation({ summary: 'Find dive sites within a radius of a coordinate' })
  nearby(@Query() query: NearbyDiveSitesDto, @Req() req: Request) {
    return this.diveSitesService.nearby(optionalToken(req), query);
  }

  @Public()
  @Get('search')
  @ApiOperation({ summary: 'Full-text search dive sites' })
  search(@Query() query: SearchDiveSitesDto, @Req() req: Request) {
    return this.diveSitesService.search(optionalToken(req), query);
  }

  @Public()
  @Get(':id/species')
  @ApiOperation({ summary: 'Species observed at a dive site' })
  getSpecies(@Param('id') id: string, @Req() req: Request) {
    return this.diveSitesService.getSpecies(optionalToken(req), id);
  }

  @Public()
  @Get(':id/sightings')
  @ApiOperation({ summary: 'Sightings at a dive site' })
  getSightings(
    @Param('id') id: string,
    @Query() query: ListSiteSightingsDto,
    @Req() req: Request,
  ) {
    return this.diveSitesService.getSightings(optionalToken(req), id, query);
  }

  @Public()
  @Get(':slugOrId')
  @ApiOperation({ summary: 'Get dive site by slug or UUID' })
  getOne(@Param('slugOrId') slugOrId: string, @Req() req: Request) {
    const token = optionalToken(req);
    const isUuid = /^[0-9a-f-]{36}$/i.test(slugOrId);
    return isUuid
      ? this.diveSitesService.getById(token, slugOrId)
      : this.diveSitesService.getBySlug(token, slugOrId);
  }

  @Post()
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Create a dive site' })
  create(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: CreateDiveSiteDto,
  ) {
    return this.diveSitesService.create(token, user.id, dto);
  }

  @Patch(':id')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Update a dive site' })
  update(
    @Param('id') id: string,
    @AccessToken() token: string,
    @Body() dto: UpdateDiveSiteDto,
  ) {
    return this.diveSitesService.update(token, id, dto);
  }

  @Delete(':id')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Delete a dive site' })
  remove(@Param('id') id: string, @AccessToken() token: string) {
    return this.diveSitesService.remove(token, id);
  }
}
