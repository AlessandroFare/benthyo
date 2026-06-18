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
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { OperatorRoles } from '../common/decorators/operator-roles.decorator';
import { Public } from '../common/decorators/public.decorator';
import { OperatorRoleGuard } from '../common/guards/operator-role.guard';
import { AuthUser } from '../common/types/auth-user.interface';
import {
  CreateOperatorDto,
  InviteOperatorUserDto,
  LinkDiveSiteDto,
  ListOperatorCustomersDto,
  ListOperatorSpeciesDto,
  ListOperatorsDto,
  OperatorAnalyticsQueryDto,
  UpdateOperatorDto,
} from './dto/operator.dto';
import { OperatorsService } from './operators.service';

function optionalToken(req: Request): string | undefined {
  const auth = req.headers.authorization;
  return auth?.startsWith('Bearer ') ? auth.slice(7).trim() : undefined;
}

@ApiTags('operators')
@Controller('operators')
export class OperatorsController {
  constructor(private readonly operatorsService: OperatorsService) {}

  @Public()
  @Get()
  @ApiOperation({ summary: 'List operators' })
  list(@Query() query: ListOperatorsDto, @Req() req: Request) {
    return this.operatorsService.list(optionalToken(req), query);
  }

  @Get('me')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Get operator profile for the authenticated user' })
  getMe(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.operatorsService.getMyOperator(token, user.id);
  }

  @Get('me/dashboard/kpis')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Dashboard KPI cards for current operator' })
  getMyDashboardKpis(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.operatorsService.getMyOperator(token, user.id).then((op) =>
      this.operatorsService.getDashboardKpis(token, op.id),
    );
  }

  @Get('me/dashboard/charts')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Dashboard charts for current operator' })
  getMyDashboardCharts(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.operatorsService.getMyOperator(token, user.id).then((op) =>
      this.operatorsService.getDashboardCharts(token, op.id),
    );
  }

  @Get('me/dashboard/activity')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Recent activity feed for current operator' })
  getMyActivity(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.operatorsService.getMyOperator(token, user.id).then((op) =>
      this.operatorsService.getRecentActivity(token, op.id),
    );
  }

  @Get('me/analytics')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Full analytics bundle for current operator' })
  getMyAnalytics(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.operatorsService.getMyOperator(token, user.id).then((op) =>
      this.operatorsService.getAnalyticsBundle(token, op.id),
    );
  }

  @Get('me/customers')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Paginated customer directory for current operator' })
  getMyCustomers(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Query() query: ListOperatorCustomersDto,
  ) {
    return this.operatorsService.getMyOperator(token, user.id).then((op) =>
      this.operatorsService.getCustomers(token, op.id, query),
    );
  }

  @Get('me/species')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Paginated species rankings for current operator' })
  getMySpecies(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Query() query: ListOperatorSpeciesDto,
  ) {
    return this.operatorsService.getMyOperator(token, user.id).then((op) =>
      this.operatorsService.getSpeciesRanked(token, op.id, query),
    );
  }

  @Public()
  @Get(':slug')
  @ApiOperation({ summary: 'Get operator by slug' })
  getBySlug(@Param('slug') slug: string, @Req() req: Request) {
    return this.operatorsService.getBySlug(optionalToken(req), slug);
  }

  @Post()
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Register a new operator' })
  create(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: CreateOperatorDto,
  ) {
    return this.operatorsService.create(token, user.id, dto);
  }

  @Patch(':operatorId')
  @UseGuards(OperatorRoleGuard)
  @OperatorRoles('owner', 'admin')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Update operator profile' })
  update(
    @Param('operatorId') operatorId: string,
    @AccessToken() token: string,
    @Body() dto: UpdateOperatorDto,
  ) {
    return this.operatorsService.update(token, operatorId, dto);
  }

  @Get(':operatorId/members')
  @UseGuards(OperatorRoleGuard)
  @OperatorRoles('owner', 'admin', 'staff')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'List operator team members' })
  getMembers(@Param('operatorId') operatorId: string, @AccessToken() token: string) {
    return this.operatorsService.getMembers(token, operatorId);
  }

  @Post(':operatorId/members')
  @UseGuards(OperatorRoleGuard)
  @OperatorRoles('owner')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Invite a user to the operator team' })
  inviteMember(
    @Param('operatorId') operatorId: string,
    @AccessToken() token: string,
    @Body() dto: InviteOperatorUserDto,
  ) {
    return this.operatorsService.inviteMember(token, operatorId, dto);
  }

  @Get(':operatorId/sites')
  @UseGuards(OperatorRoleGuard)
  @OperatorRoles('owner', 'admin', 'staff')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'List dive sites linked to operator' })
  getSites(@Param('operatorId') operatorId: string, @AccessToken() token: string) {
    return this.operatorsService.getSites(token, operatorId);
  }

  @Post(':operatorId/sites')
  @UseGuards(OperatorRoleGuard)
  @OperatorRoles('owner', 'admin', 'staff')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Link a dive site to operator' })
  linkSite(
    @Param('operatorId') operatorId: string,
    @AccessToken() token: string,
    @Body() dto: LinkDiveSiteDto,
  ) {
    return this.operatorsService.linkSite(token, operatorId, dto);
  }

  @Delete(':operatorId/sites/:diveSiteId')
  @UseGuards(OperatorRoleGuard)
  @OperatorRoles('owner', 'admin', 'staff')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Unlink a dive site from operator' })
  unlinkSite(
    @Param('operatorId') operatorId: string,
    @Param('diveSiteId') diveSiteId: string,
    @AccessToken() token: string,
  ) {
    return this.operatorsService.unlinkSite(token, operatorId, diveSiteId);
  }

  @Get(':operatorId/analytics/kpis')
  @UseGuards(OperatorRoleGuard)
  @OperatorRoles('owner', 'admin', 'staff')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Operator KPI dashboard metrics' })
  getKpis(
    @Param('operatorId') operatorId: string,
    @AccessToken() token: string,
    @Query() query: OperatorAnalyticsQueryDto,
  ) {
    return this.operatorsService.getKpis(token, operatorId, query);
  }

  @Get(':operatorId/analytics/dives-by-month')
  @UseGuards(OperatorRoleGuard)
  @OperatorRoles('owner', 'admin', 'staff')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Monthly dive counts for operator dashboard chart' })
  getDivesByMonth(
    @Param('operatorId') operatorId: string,
    @AccessToken() token: string,
  ) {
    return this.operatorsService.getDivesByMonth(token, operatorId);
  }

  /**
   * Soft-delete the caller's primary operator. Only owners can do this
   * for their own operator. Use the admin purge route for hard delete.
   */
  @Delete('me')
  @UseGuards(OperatorRoleGuard)
  @OperatorRoles('owner')
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Soft-delete the caller\u2019s primary operator' })
  async deleteMyOperator(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body('reason') reason?: string,
  ) {
    const op = await this.operatorsService.getMyOperator(token, user.id);
    return this.operatorsService.softDeleteMyOperator(token, op.id, reason);
  }
}
