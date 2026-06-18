import { Module } from '@nestjs/common';
import { DiveSitesController } from './dive-sites.controller';
import { DiveSitesService } from './dive-sites.service';

@Module({
  controllers: [DiveSitesController],
  providers: [DiveSitesService],
  exports: [DiveSitesService],
})
export class DiveSitesModule {}
