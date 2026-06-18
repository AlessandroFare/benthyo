import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Public } from '../common/decorators/public.decorator';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { CorrectionsService } from './corrections.service';
import { SuggestCorrectionDto } from './dto/correction.dto';

@ApiTags('corrections')
@Controller('corrections')
export class CorrectionsController {
  constructor(private readonly corrections: CorrectionsService) {}

  @Post()
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Suggest a species ID correction' })
  suggest(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: SuggestCorrectionDto,
  ) {
    return this.corrections.suggest(token, user.id, dto);
  }

  @Post(':id/accept')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Accept a correction (sighting owner)' })
  accept(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id') id: string,
  ) {
    return this.corrections.accept(token, user.id, id);
  }

  @Get('expert/queue')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Open corrections queue (taxonomy experts)' })
  expertQueue(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.corrections.listOpenForExpert(token, user.id);
  }

  @Post(':id/expert-resolve')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Expert accept or reject a correction' })
  expertResolve(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id') id: string,
    @Body() body: { action: 'accept' | 'reject' },
  ) {
    return this.corrections.expertResolve(token, user.id, id, body.action);
  }

  @Public()
  @Get('sighting/:sightingId')
  @ApiOperation({ summary: 'List corrections for a sighting' })
  listForSighting(@Param('sightingId') sightingId: string) {
    return this.corrections.listForSighting(undefined, sightingId);
  }
}
