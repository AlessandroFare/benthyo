import { Module } from '@nestjs/common';
import { CertCardsController } from './cert-cards.controller';
import { CertCardsService } from './cert-cards.service';

@Module({
  controllers: [CertCardsController],
  providers: [CertCardsService],
})
export class CertCardsModule {}
