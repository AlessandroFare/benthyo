import { Injectable, Logger, BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import Stripe from 'stripe';

/**
 * Stripe webhook + billing-side state transitions.
 *
 * Implements:
 *   - Signature verification via stripe.webhooks.constructEvent
 *   - invoice.paid -> mark operator_payment_links.paid_at + status
 *   - customer.subscription.created/updated -> set_operator_subscription
 *   - customer.subscription.deleted -> set_operator_subscription(canceled)
 */
@Injectable()
export class StripeService {
  private readonly logger = new Logger(StripeService.name);
  private readonly stripe: Stripe;
  private readonly webhookSecret: string;

  constructor(private readonly configService: ConfigService) {
    const secretKey = this.configService.get<string>('STRIPE_SECRET_KEY') ?? '';
    this.webhookSecret =
      this.configService.get<string>('STRIPE_WEBHOOK_SECRET') ?? '';
    if (!secretKey) {
      this.logger.warn('STRIPE_SECRET_KEY is not set; Stripe is disabled');
      this.stripe = null as unknown as Stripe;
      return;
    }
    this.stripe = new Stripe(secretKey, { apiVersion: '2025-02-24.acacia' });
  }

  /**
   * Verify the Stripe signature and dispatch the event to the right
   * handler. Returns 200 on success, 4xx on signature failure.
   */
  async handleWebhook(
    _req: unknown,
    signature: string | undefined,
    rawBody: Buffer,
  ): Promise<{ received: true; event_type: string }> {
    if (!this.stripe) {
      throw new BadRequestException('Stripe is not configured');
    }
    if (!signature) {
      throw new BadRequestException('Missing stripe-signature header');
    }
    if (!this.webhookSecret) {
      throw new BadRequestException('Webhook secret not configured');
    }
    let event: Stripe.Event;
    try {
      event = this.stripe.webhooks.constructEvent(
        rawBody,
        signature,
        this.webhookSecret,
      );
    } catch (err) {
      throw new BadRequestException(
        `Stripe signature verification failed: ${(err as Error).message}`,
      );
    }

    const admin = createClient(
      this.configService.get<string>('SUPABASE_URL')!,
      this.configService.get<string>('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false } },
    );

    switch (event.type) {
      case 'invoice.paid': {
        const invoice = event.data.object as Stripe.Invoice;
        // The invoice's metadata or description carries our payment_link
        // id (set when the operator created the link).
        const linkId =
          (invoice.metadata?.operator_payment_link_id as string | undefined) ??
          null;
        if (linkId) {
          await admin
            .from('operator_payment_links')
            .update({ paid_at: new Date().toISOString() })
            .eq('id', linkId);
        }
        // If the invoice corresponds to a subscription, mark the
        // operator's subscription as active.
        if (invoice.subscription && typeof invoice.subscription === 'string') {
          const subId = invoice.subscription;
          await this.applySubscription(admin, subId, 'active', invoice.metadata);
        }
        break;
      }
      case 'customer.subscription.created':
      case 'customer.subscription.updated': {
        const sub = event.data.object as Stripe.Subscription;
        // Map Stripe statuses onto our 4-value enum. The DB enum is
        // 'active' | 'past_due' | 'canceled' | 'trialing'.
        const mapped: 'active' | 'past_due' | 'canceled' | 'trialing' =
          sub.status === 'active' || sub.status === 'trialing'
            ? sub.status
            : sub.status === 'past_due' || sub.status === 'unpaid'
              ? 'past_due'
              : 'canceled';
        await this.applySubscription(admin, sub.id, mapped, sub.metadata);
        break;
      }
      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription;
        await this.applySubscription(admin, sub.id, 'canceled', sub.metadata);
        break;
      }
      case 'payment_intent.succeeded': {
        const pi = event.data.object as Stripe.PaymentIntent;
        const bookingId = pi.metadata?.booking_id;
        if (bookingId) {
          await admin.rpc('confirm_booking', {
            p_booking_id: bookingId,
            p_payment_intent_id: pi.id,
            p_client_secret: pi.client_secret ?? null,
          });
          this.logger.log(`Booking ${bookingId} confirmed via Stripe PI ${pi.id}`);
        }
        break;
      }
      case 'payment_intent.payment_failed': {
        const failedPi = event.data.object as Stripe.PaymentIntent;
        const failedBookingId = failedPi.metadata?.booking_id;
        if (failedBookingId) {
          await admin.rpc('cancel_booking', { p_booking_id: failedBookingId });
          this.logger.warn(`Booking ${failedBookingId} cancelled due to failed payment`);
        }
        break;
      }
      default:
        this.logger.debug(`Unhandled Stripe event type: ${event.type}`);
    }

    return { received: true, event_type: event.type };
  }

  /**
   * Map a Stripe subscription to an operator and update their tier.
   */
  private async applySubscription(
    admin: SupabaseClient<any, 'public', any>,
    stripeSubId: string,
    status: 'active' | 'past_due' | 'canceled' | 'trialing',
    metadata: Stripe.Metadata | null,
  ) {
    const operatorId = metadata?.operator_id;
    if (!operatorId) {
      this.logger.warn(
        `Stripe subscription ${stripeSubId} has no operator_id metadata; skipping`,
      );
      return;
    }
    const tier = (metadata?.tier as string | undefined) ?? 'starter';
    // The set_operator_subscription function is SECURITY DEFINER; we
    // call it as service role.
    const { error } = await admin.rpc('set_operator_subscription', {
      p_operator_id: operatorId,
      p_tier: tier,
      p_status: status,
    });
    if (error) {
      this.logger.error(
        `Failed to set operator ${operatorId} subscription to ${status}/${tier}: ${error.message}`,
      );
    }
  }
}
