import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Put,
  Req,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Request } from 'express';
import { Public } from '../common/decorators/public.decorator';
import {
  CurrentUser,
  AccessToken,
} from '../common/decorators/current-user.decorator';
import { OperatorRoleGuard } from '../common/guards/operator-role.guard';
import { OperatorRoles } from '../common/decorators/operator-roles.decorator';
import { TierGuard, RequireTier } from '../common/guards/tier.guard';
import { AuthUser } from '../common/types/auth-user.interface';
import { SignWaiverDto, UpsertOperatorWaiverDto } from './dto/waiver.dto';
import { WaiversService } from './waivers.service';

@ApiTags('waivers')
@Controller('waivers')
export class WaiversController {
  constructor(private readonly waiversService: WaiversService) {}

  @Public()
  @Get('operator/:slug')
  @ApiOperation({ summary: 'Active waiver for QR / guest sign flow' })
  getBySlug(@Param('slug') slug: string) {
    return this.waiversService.getActiveByOperatorSlug(slug);
  }

  @Get('operator/:slug/manage')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Active waiver for operator dashboard editor' })
  getForManage(@Param('slug') slug: string, @AccessToken() token: string) {
    return this.waiversService.getActiveByOperatorSlug(slug);
  }

  /**
   * Publish a new waiver version. Now requires the caller to be an
   * owner or admin of the operator (defense in depth — RLS catches
   * cross-tenant calls but the controller should be explicit).
   */
  // Compliance bundle (waivers + medical) is a paid capability. Publishing
  // a waiver version requires the 'pro' tier in addition to owner/admin
  // role. TierGuard resolves the operator from :operatorId and enforces an
  // active (or grace-period) subscription.
  @Put('operator/:operatorId')
  @ApiBearerAuth()
  @UseGuards(OperatorRoleGuard, TierGuard)
  @OperatorRoles('owner', 'admin')
  @RequireTier('pro')
  @ApiOperation({ summary: 'Publish a new waiver version for an operator' })
  upsert(
    @Param('operatorId', new ParseUUIDPipe()) operatorId: string,
    @AccessToken() token: string,
    @Body() dto: UpsertOperatorWaiverDto,
  ) {
    return this.waiversService.upsertForOperator(token, operatorId, dto);
  }

  /**
   * Sign a waiver. Captures IP and User-Agent server-side for legal
   * binding (DD-5.7). The signature row stores the IP, the user agent,
   * the signer email, and a SHA256 of the waiver body at the time of
   * signing so any subsequent change to the waiver body is detectable.
   */
  @Post('sign')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Sign an operator waiver (authenticated guest)' })
  sign(
    @Req() req: Request,
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: SignWaiverDto,
  ) {
    return this.waiversService.sign(token, user.id, dto, {
      ip: req.ip ?? 'unknown',
      userAgent: req.headers['user-agent'] ?? 'unknown',
    });
  }
}
