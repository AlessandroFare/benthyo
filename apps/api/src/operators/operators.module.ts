import { Module } from '@nestjs/common';
import { OperatorRoleGuard } from '../common/guards/operator-role.guard';
import { OperatorsController } from './operators.controller';
import { OperatorsService } from './operators.service';

@Module({
  controllers: [OperatorsController],
  providers: [OperatorsService, OperatorRoleGuard],
  exports: [OperatorsService],
})
export class OperatorsModule {}
