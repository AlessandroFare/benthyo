import { Module } from '@nestjs/common';
import { SpeciesController } from './species.controller';
import { SpeciesService } from './species.service';
import { AiVisionService } from './ai-vision.service';

@Module({
  controllers: [SpeciesController],
  providers: [SpeciesService, AiVisionService],
  exports: [SpeciesService],
})
export class SpeciesModule {}
