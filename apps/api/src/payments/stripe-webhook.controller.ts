import {
  Body,
  Controller,
  Headers,
  HttpCode,
  Post,
  Req,
} from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Public } from '../common/decorators/public.decorator';
import { StripeService } from './stripe.service';
import { Request } from 'express';

@ApiTags('billing')
@Controller('billing')
export class StripeWebhookController {
  constructor(private readonly stripe: StripeService) {}

  /**
   * Stripe webhook receiver. The route is public (Stripe doesn't carry
   * a Supabase JWT) but verifies the Stripe signature against
   * STRIPE_WEBHOOK_SECRET. Rejects any payload that doesn't validate.
   *
   * Handles:
   *   - invoice.paid         -> mark the matching payment_links row paid
   *   - customer.subscription.created
   *   - customer.subscription.updated
   *   - customer.subscription.deleted
   * Each of those updates the operator's subscription_status / tier via
   * the privileged set_operator_subscription function (SECURITY
   * DEFINER; only callable by the `subscription_admin` role).
   */
  @Public()
  @Post('stripe/webhook')
  @HttpCode(200)
  @ApiOperation({ summary: 'Stripe webhook receiver' })
  async webhook(
    @Req() req: Request,
    @Headers('stripe-signature') signature: string,
    @Body() rawBody: Buffer,
  ) {
    return this.stripe.handleWebhook(req, signature, rawBody);
  }
}
