import { Module } from '@nestjs/common';
import { DiveLogsModule } from '../dive-logs/dive-logs.module';
import { BleSyncController } from './ble-sync.controller';
import { BleSyncService } from './ble-sync.service';

@Module({
  imports: [DiveLogsModule],
  controllers: [BleSyncController],
  providers: [BleSyncService],
})
export class BleSyncModule {}
