import { Body, Controller, Get, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { BleImportDto, RegisterBleDeviceDto } from './dto/ble-sync.dto';
import { BleSyncService } from './ble-sync.service';

@ApiTags('ble-sync')
@ApiBearerAuth()
@Controller('dive-computers')
export class BleSyncController {
  constructor(private readonly bleSync: BleSyncService) {}

  @Get()
  @ApiOperation({ summary: 'List paired BLE dive computers' })
  listDevices(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.bleSync.listDevices(token, user.id);
  }

  @Post('register')
  @ApiOperation({ summary: 'Register a paired BLE dive computer' })
  register(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: RegisterBleDeviceDto,
  ) {
    return this.bleSync.registerDevice(token, user.id, dto);
  }

  @Post('import')
  @ApiOperation({ summary: 'Import dives synced from a BLE dive computer' })
  importDives(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: BleImportDto,
  ) {
    return this.bleSync.importDives(token, user.id, dto);
  }
}
