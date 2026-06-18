import { Controller, Get, Query, Req } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Request } from 'express';
import { Public } from '../common/decorators/public.decorator';
import { UnifiedSearchDto } from './dto/search.dto';
import { SearchService } from './search.service';

function optionalToken(req: Request): string | undefined {
  const auth = req.headers.authorization;
  return auth?.startsWith('Bearer ') ? auth.slice(7).trim() : undefined;
}

@ApiTags('search')
@Controller('search')
export class SearchController {
  constructor(private readonly searchService: SearchService) {}

  @Public()
  @Get()
  @ApiOperation({ summary: 'Unified full-text search across dive sites and species' })
  search(@Query() query: UnifiedSearchDto, @Req() req: Request) {
    return this.searchService.search(optionalToken(req), query);
  }
}
