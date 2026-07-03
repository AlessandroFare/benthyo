import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { TierGuard, RequireTier } from '../common/guards/tier.guard';
import { AuthUser } from '../common/types/auth-user.interface';
import { OperatorsService } from '../operators/operators.service';
import { RentalGearService } from './rental-gear.service';

// Rental gear is a Pro-tier capability. The whole controller is gated so
// registration, checkout, and checkin all require an active 'pro'
// subscription. TierGuard resolves the caller's primary operator.
@ApiTags('rental-gear')
@ApiBearerAuth()
@UseGuards(TierGuard)
@RequireTier('pro')
@Controller('operators/me/rental-gear')
export class RentalGearController {
  constructor(
    private readonly rentalGear: RentalGearService,
    private readonly operators: OperatorsService,
  ) {}

  @Get()
  @ApiOperation({ summary: 'List operator rental gear' })
  async list(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    const op = await this.operators.getMyOperator(token, user.id);
    return this.rentalGear.list(token, op.id);
  }

  @Post()
  @ApiOperation({ summary: 'Register rental gear with QR code' })
  async create(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: { gear_type: string; label: string; serial_number?: string },
  ) {
    const op = await this.operators.getMyOperator(token, user.id);
    return this.rentalGear.create(token, op.id, dto);
  }

  @Post(':qrCode/checkout')
  @ApiOperation({ summary: 'Check out gear to a diver' })
  async checkout(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('qrCode') qrCode: string,
    @Body() body: { user_id: string },
  ) {
    const op = await this.operators.getMyOperator(token, user.id);
    return this.rentalGear.checkout(token, op.id, qrCode, body.user_id);
  }

  @Post(':qrCode/checkin')
  @ApiOperation({ summary: 'Check in returned gear' })
  async checkin(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('qrCode') qrCode: string,
  ) {
    const op = await this.operators.getMyOperator(token, user.id);
    return this.rentalGear.checkin(token, op.id, qrCode);
  }
}
