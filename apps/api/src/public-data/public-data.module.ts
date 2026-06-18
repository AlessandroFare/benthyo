import { Module } from '@nestjs/common';
import { DiveSitesModule } from '../dive-sites/dive-sites.module';
import { PublicDataController } from './public-data.controller';
import { PublicDataService } from './public-data.service';

@Module({
  imports: [DiveSitesModule],
  controllers: [PublicDataController],
  providers: [PublicDataService],
  exports: [PublicDataService],
})
export class PublicDataModule {}
