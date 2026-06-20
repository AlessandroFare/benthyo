import { Body, Controller, Delete, Get, Param, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { TierGuard, RequireTier } from '../common/guards/tier.guard';
import { AuthUser } from '../common/types/auth-user.interface';
import { CreateApiKeyDto } from '../medical/dto/medical.dto';
import { ApiKeysService } from './api-keys.service';

@ApiTags('api-keys')
@ApiBearerAuth()
@Controller('api-keys')
export class ApiKeysController {
  constructor(private readonly apiKeys: ApiKeysService) {}

  @Get()
  @ApiOperation({ summary: 'List my API keys' })
  list(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.apiKeys.list(token, user.id);
  }

  // Minting API keys is a Pro-tier capability. Listing and revoking
  // existing keys stay available to any authenticated operator so a
  // downgraded account can still see and revoke keys it already created.
  @Post()
  @UseGuards(TierGuard)
  @RequireTier('pro')
  @ApiOperation({ summary: 'Create a read API key (shown once)' })
  create(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: CreateApiKeyDto,
  ) {
    return this.apiKeys.create(token, user.id, dto);
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Revoke an API key' })
  revoke(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id') id: string,
  ) {
    return this.apiKeys.revoke(token, user.id, id);
  }
}
