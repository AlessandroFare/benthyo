import { Module } from '@nestjs/common';
import { SightingsController } from './sightings.controller';
import { SightingsService } from './sightings.service';

@Module({
  controllers: [SightingsController],
  providers: [SightingsService],
  exports: [SightingsService],
})
export class SightingsModule {}
