import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { CreateGearItemDto, UpdateGearItemDto } from './dto/gear.dto';
import { GearService } from './gear.service';

@ApiTags('gear')
@ApiBearerAuth()
@Controller('gear')
export class GearController {
  constructor(private readonly gear: GearService) {}

  @Get()
  @ApiOperation({ summary: 'List my gear items' })
  list(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.gear.list(token, user.id);
  }

  @Get('service-due')
  @ApiOperation({ summary: 'Gear items due for service' })
  serviceDue(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.gear.listServiceDue(token, user.id);
  }

  @Post()
  @ApiOperation({ summary: 'Add gear item' })
  create(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: CreateGearItemDto,
  ) {
    return this.gear.create(token, user.id, dto);
  }

  @Patch(':id')
  @ApiOperation({ summary: 'Update gear item' })
  update(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id') id: string,
    @Body() dto: UpdateGearItemDto,
  ) {
    return this.gear.update(token, user.id, id, dto);
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Delete gear item' })
  delete(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id') id: string,
  ) {
    return this.gear.delete(token, user.id, id);
  }
}
