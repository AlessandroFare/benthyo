import { Body, Controller, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Public } from '../common/decorators/public.decorator';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { TierGuard, RequireTier } from '../common/guards/tier.guard';
import { AuthUser } from '../common/types/auth-user.interface';
import { OperatorsService } from '../operators/operators.service';
import {
  CreateMarketplaceListingDto,
  UpdateMarketplaceListingDto,
} from './dto/marketplace.dto';
import { MarketplaceService } from './marketplace.service';

@ApiTags('marketplace')
@Controller()
export class MarketplaceController {
  constructor(
    private readonly marketplace: MarketplaceService,
    private readonly operators: OperatorsService,
  ) {}

  @Public()
  @Get('marketplace/listings')
  @ApiOperation({ summary: 'Browse operator marketplace listings' })
  listPublic(
    @Query('region') region?: string,
    @Query('type') type?: string,
  ) {
    return this.marketplace.listPublic(region, type);
  }

  @Get('operators/me/marketplace')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Operator marketplace listings (dashboard)' })
  async listMine(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    const op = await this.operators.getMyOperator(token, user.id);
    return this.marketplace.listForOperator(token, op.id);
  }

  @Post('operators/me/marketplace')
  @ApiBearerAuth()
  @UseGuards(TierGuard)
  @RequireTier('pro')
  @ApiOperation({ summary: 'Create marketplace listing' })
  async create(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: CreateMarketplaceListingDto,
  ) {
    const op = await this.operators.getMyOperator(token, user.id);
    return this.marketplace.create(token, op.id, dto);
  }

  @Patch('operators/me/marketplace/:id')
  @ApiBearerAuth()
  @UseGuards(TierGuard)
  @RequireTier('pro')
  @ApiOperation({ summary: 'Update marketplace listing' })
  async update(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id') id: string,
    @Body() dto: UpdateMarketplaceListingDto,
  ) {
    const op = await this.operators.getMyOperator(token, user.id);
    return this.marketplace.update(token, op.id, id, dto);
  }
}
