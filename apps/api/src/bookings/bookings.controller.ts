import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { Public } from '../common/decorators/public.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { OperatorsService } from '../operators/operators.service';
import { BookingsService } from './bookings.service';
import {
  CreateBookingSlotDto,
  UpdateBookingSlotDto,
  CreateBookingDto,
  SlotQueryDto,
} from './dto/bookings.dto';

@ApiTags('bookings')
@ApiBearerAuth()
@Controller()
export class BookingsController {
  constructor(
    private readonly bookings: BookingsService,
    private readonly operators: OperatorsService,
  ) {}

  @Public()
  @Get('public/slots')
  @ApiOperation({ summary: 'Browse available booking slots (public)' })
  browseSlots(@Query() query: SlotQueryDto) {
    return this.bookings.browseSlots(null, query);
  }

  @Get('operators/me/slots')
  @ApiOperation({ summary: 'List slots for my operator' })
  async listSlots(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Query() query: SlotQueryDto,
  ) {
    const op = await this.operators.getMyOperator(token, user.id);
    return this.bookings.listSlots(token, op.id, query);
  }

  @Post('operators/me/slots')
  @ApiOperation({ summary: 'Create a bookable slot' })
  async createSlot(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: CreateBookingSlotDto,
  ) {
    const op = await this.operators.getMyOperator(token, user.id);
    return this.bookings.createSlot(token, user.id, op.id, dto);
  }

  @Patch('operators/me/slots/:slotId')
  @ApiOperation({ summary: 'Update a slot' })
  async updateSlot(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('slotId') slotId: string,
    @Body() dto: UpdateBookingSlotDto,
  ) {
    const op = await this.operators.getMyOperator(token, user.id);
    return this.bookings.updateSlot(token, op.id, slotId, dto);
  }

  @Delete('operators/me/slots/:slotId')
  @ApiOperation({ summary: 'Delete a slot' })
  async deleteSlot(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('slotId') slotId: string,
  ) {
    const op = await this.operators.getMyOperator(token, user.id);
    return this.bookings.deleteSlot(token, op.id, slotId);
  }

  @Post('bookings')
  @ApiOperation({ summary: 'Create a booking (triggers Stripe PaymentIntent)' })
  createBooking(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: CreateBookingDto,
  ) {
    return this.bookings.createBooking(token, user.id, dto);
  }

  @Get('bookings')
  @ApiOperation({ summary: 'List my bookings' })
  listMyBookings(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
  ) {
    return this.bookings.listMyBookings(token, user.id);
  }

  @Get('bookings/:id')
  @ApiOperation({ summary: 'Get booking details' })
  getBooking(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id') id: string,
  ) {
    return this.bookings.getBooking(token, user.id, id);
  }

  @Post('bookings/:id/cancel')
  @ApiOperation({ summary: 'Cancel a booking' })
  cancelBooking(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id') id: string,
  ) {
    return this.bookings.cancelBooking(token, user.id, id);
  }
}
