import { Controller, Get, Param } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Public } from '../common/decorators/public.decorator';
import { PublicDataService } from './public-data.service';

@ApiTags('public')
@Controller('public')
export class PublicDataController {
  constructor(private readonly publicData: PublicDataService) {}

  @Public()
  @Get('sites/:slugOrId/card')
  @ApiOperation({ summary: 'Embeddable site data card (dives, species, stats)' })
  getSiteCard(@Param('slugOrId') slugOrId: string) {
    return this.publicData.getSiteCard(slugOrId);
  }

  @Public()
  @Get('sites/:slugOrId/prep-card')
  @ApiOperation({ summary: 'Pre-dive prep card (conditions, reviews, species)' })
  getPrepCard(@Param('slugOrId') slugOrId: string) {
    return this.publicData.getPrepCard(slugOrId);
  }

  @Public()
  @Get('operators/:slug/briefing')
  @ApiOperation({ summary: 'Guest briefing card for QR embed (waiver + medical links)' })
  getGuestBriefing(@Param('slug') slug: string) {
    return this.publicData.getGuestBriefing(slug);
  }

  @Public()
  @Get('users/:userId/verification')
  @ApiOperation({ summary: 'Diver verification level (data quality signal)' })
  getVerification(@Param('userId') userId: string) {
    return this.publicData.getDiverVerification(userId);
  }
}
