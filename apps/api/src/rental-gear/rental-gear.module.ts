import { Module } from '@nestjs/common';
import { OperatorsModule } from '../operators/operators.module';
import { RentalGearController } from './rental-gear.controller';
import { RentalGearService } from './rental-gear.service';

@Module({
  imports: [OperatorsModule],
  controllers: [RentalGearController],
  providers: [RentalGearService],
})
export class RentalGearModule {}
