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
import { AuthUser } from '../common/types/auth-user.interface';
import {
  CreateDiveLogDto,
  ListDiveLogsDto,
  SyncDiveLogsDto,
  UpdateDiveLogDto,
} from './dto/dive-log.dto';
import { DiveLogsService } from './dive-logs.service';

@ApiTags('dive-logs')
@ApiBearerAuth()
@Controller('dive-logs')
export class DiveLogsController {
  constructor(private readonly diveLogsService: DiveLogsService) {}

  @Get()
  @ApiOperation({ summary: 'List own dive logs' })
  list(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Query() query: ListDiveLogsDto,
  ) {
    return this.diveLogsService.list(token, user.id, query);
  }

  @Get('stats')
  @ApiOperation({ summary: 'Aggregate dive statistics' })
  stats(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    return this.diveLogsService.getStats(token, user.id);
  }

  @Post('sync')
  @ApiOperation({ summary: 'Bulk sync dive logs from offline queue' })
  sync(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: SyncDiveLogsDto,
  ) {
    return this.diveLogsService.sync(token, user.id, dto);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get dive log detail' })
  getById(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id') id: string,
  ) {
    return this.diveLogsService.getById(token, user.id, id);
  }

  @Post()
  @ApiOperation({ summary: 'Create a dive log' })
  create(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: CreateDiveLogDto,
  ) {
    return this.diveLogsService.create(token, user.id, dto);
  }

  @Patch(':id')
  update(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id') id: string,
    @Body() dto: UpdateDiveLogDto,
  ) {
    return this.diveLogsService.update(token, user.id, id, dto);
  }

  @Delete(':id')
  remove(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id') id: string,
  ) {
    return this.diveLogsService.remove(token, user.id, id);
  }
}
