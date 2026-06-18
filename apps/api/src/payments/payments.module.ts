import { Module } from '@nestjs/common';
import { OperatorsModule } from '../operators/operators.module';
import { PaymentsController } from './payments.controller';
import { PaymentsService } from './payments.service';
import { StripeService } from './stripe.service';
import { StripeWebhookController } from './stripe-webhook.controller';

@Module({
  imports: [OperatorsModule],
  controllers: [PaymentsController, StripeWebhookController],
  providers: [PaymentsService, StripeService],
  exports: [StripeService],
})
export class PaymentsModule {}
