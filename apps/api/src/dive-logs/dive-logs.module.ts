import { Module } from '@nestjs/common';
import { DiveLogsController } from './dive-logs.controller';
import { DiveLogImportController } from './dive-log-import.controller';
import { DiveLogsService } from './dive-logs.service';
import { DiveLogImportService } from './dive-log-import.service';

@Module({
  controllers: [DiveLogsController, DiveLogImportController],
  providers: [DiveLogsService, DiveLogImportService],
  exports: [DiveLogsService],
})
export class DiveLogsModule {}
