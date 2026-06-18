import { Controller, Get, Patch, Body, Param, Req, Delete, Res, HttpCode } from '@nestjs/common';
import { Request, Response } from 'express';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { Public } from '../common/decorators/public.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { UpdateUserDto } from './dto/update-user.dto';
import { UsersService } from './users.service';
import { GdprService } from './gdpr.service';
import { IsString } from 'class-validator';

class DeleteAccountDto {
  /** Must equal "DELETE MY ACCOUNT" exactly. */
  @IsString()
  confirm!: string;
}

@ApiTags('users')
@ApiBearerAuth()
@Controller('users')
export class UsersController {
  constructor(
    private readonly usersService: UsersService,
    private readonly gdpr: GdprService,
  ) {}

  @Get('me')
  @ApiOperation({ summary: 'Get the authenticated user profile' })
  getMe(@AccessToken() token: string) {
    return this.usersService.getMe(token);
  }

  @Patch('me')
  @ApiOperation({ summary: 'Update the authenticated user profile' })
  updateMe(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: UpdateUserDto,
  ) {
    return this.usersService.updateMe(token, user.id, dto);
  }

  /**
   * GDPR Article 15 — Right of access. Returns a JSON download of
   * every user-scoped record.
   */
  @Get('me/export')
  @ApiOperation({
    summary: 'GDPR Article 15 export — full JSON dump of all user data',
  })
  async exportMe(
    @CurrentUser() user: AuthUser,
    @Res({ passthrough: false }) res: Response,
  ) {
    const payload = await this.gdpr.exportUserData(user.id);
    res.setHeader('Content-Type', 'application/json');
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="oceanlog-export-${user.id}-${Date.now()}.json"`,
    );
    res.send(JSON.stringify(payload, null, 2));
  }

  /**
   * GDPR Article 17 — Right to erasure. Caller must POST
   * { confirm: "DELETE MY ACCOUNT" } in the body.
   */
  @Delete('me')
  @HttpCode(200)
  @ApiOperation({
    summary: 'GDPR Article 17 erasure — permanently delete the account',
  })
  async deleteMe(
    @CurrentUser() user: AuthUser,
    @Body() dto: DeleteAccountDto,
  ) {
    return this.gdpr.eraseUser(
      user.id,
      user.id,
      // Caller is always the user themselves on this route; admin
      // uses /v1/admin/erase/:userId (TODO if needed).
      false,
      dto.confirm,
    );
  }

  @Get('me/life-list')
  @ApiOperation({ summary: 'Get the authenticated user life list' })
  getLifeList(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.usersService.getLifeList(token, user.id);
  }

  @Get('me/badges')
  @ApiOperation({ summary: 'Get badges earned by the authenticated user' })
  getBadges(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.usersService.getBadges(token, user.id);
  }

  @Get('me/conservation-alerts')
  @ApiOperation({ summary: 'CR/EN species alerts near your dive regions' })
  getConservationAlerts(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
  ) {
    return this.usersService.getConservationAlerts(token, user.id);
  }

  @Public()
  @Get(':username/logbook')
  @ApiOperation({ summary: 'Public verifiable logbook URL data' })
  getPublicLogbook(@Param('username') username: string, @Req() req: Request) {
    const auth = req.headers.authorization;
    const token = auth?.startsWith('Bearer ') ? auth.slice(7).trim() : undefined;
    return this.usersService.getPublicLogbook(token, username);
  }

  @Public()
  @Get(':username')
  @ApiOperation({ summary: 'Get a public user profile by username' })
  getByUsername(@Param('username') username: string, @Req() req: Request) {
    const auth = req.headers.authorization;
    const token = auth?.startsWith('Bearer ') ? auth.slice(7).trim() : undefined;
    return this.usersService.getByUsername(token, username);
  }
}
