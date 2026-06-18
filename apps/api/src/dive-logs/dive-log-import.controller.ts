import { Body, Controller, HttpCode, PayloadTooLargeException, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { Throttle } from '@nestjs/throttler';
import { ImportUddfDto } from './dto/import-uddf.dto';
import { DiveLogImportService } from './dive-log-import.service';

const MAX_UDDF_BYTES = 5 * 1024 * 1024; // 5MB

@ApiTags('dive-logs')
@ApiBearerAuth()
@Controller('dive-logs')
export class DiveLogImportController {
  constructor(private readonly importService: DiveLogImportService) {}

  @Post('import/uddf')
  @HttpCode(202)
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @ApiOperation({
    summary: 'Import dives from UDDF/UDCF XML (Suunto, Shearwater, Garmin)',
  })
  importUddf(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Body() dto: ImportUddfDto,
  ) {
    // H-8: the previous implementation had no body cap. A 1GB XML file
    // would pin the event loop. Validate byte length up front.
    const bytes = Buffer.byteLength(dto.xml, 'utf8');
    if (bytes > MAX_UDDF_BYTES) {
      throw new PayloadTooLargeException(
        `UDDF payload too large: ${bytes} bytes (max ${MAX_UDDF_BYTES})`,
      );
    }
    return this.importService.importUddf(token, user.id, dto.xml);
  }
}
