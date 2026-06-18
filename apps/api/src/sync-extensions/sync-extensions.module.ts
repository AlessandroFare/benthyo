import { Module } from '@nestjs/common';
import { SyncExtensionsController } from './sync-extensions.controller';
import { SyncExtensionsService } from './sync-extensions.service';
import { SyncDeadLetterController } from './sync-dead-letter.controller';
import { ApiKeysModule } from '../api-keys/api-keys.module';

@Module({
  imports: [ApiKeysModule],
  controllers: [SyncExtensionsController, SyncDeadLetterController],
  providers: [SyncExtensionsService],
  exports: [SyncExtensionsService],
})
export class SyncExtensionsModule {}