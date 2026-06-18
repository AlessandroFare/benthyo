import { Body, Controller, Get, Header, Param, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { CreateTripDto } from '../gear/dto/gear.dto';
import { TripsService } from './trips.service';

@ApiTags('trips')
@ApiBearerAuth()
@Controller('trips')
export class TripsController {
  constructor(private readonly trips: TripsService) {}

  @Get()
  @ApiOperation({ summary: 'List my trips' })
  list(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.trips.list(token, user.id);
  }

  @Post()
  @ApiOperation({ summary: 'Create a group trip' })
  create(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: CreateTripDto,
  ) {
    return this.trips.create(token, user.id, dto);
  }

  @Get(':id/calendar.ics')
  @ApiOperation({ summary: 'Download trip as iCalendar (.ics)' })
  @Header('Content-Type', 'text/calendar; charset=utf-8')
  @Header('Content-Disposition', 'attachment; filename="trip.ics"')
  async getCalendar(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id') id: string,
  ) {
    return this.trips.getCalendarIcs(token, user.id, id);
  }

  @Post(':id/members')
  @ApiOperation({ summary: 'Invite a diver to the trip by username' })
  inviteMember(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id') id: string,
    @Body() body: { username: string },
  ) {
    return this.trips.inviteMember(token, user.id, id, body.username);
  }

  @Get(':id/recap')
  @ApiOperation({ summary: 'Post-trip recap stats' })
  getRecap(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id') id: string,
  ) {
    return this.trips.getRecap(token, user.id, id);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get trip with members and sites' })
  getById(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id') id: string,
  ) {
    return this.trips.getById(token, user.id, id);
  }
}
