import {
  Injectable,
  Logger,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Stripe from 'stripe';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';
import type { CreateBookingSlotDto, UpdateBookingSlotDto, CreateBookingDto, SlotQueryDto } from './dto/bookings.dto';

@Injectable()
export class BookingsService {
  private readonly logger = new Logger(BookingsService.name);
  private readonly stripe: Stripe | null = null;

  constructor(
    private readonly supabase: SupabaseService,
    private readonly configService: ConfigService,
  ) {
    const secretKey = this.configService.get<string>('STRIPE_SECRET_KEY') ?? '';
    if (secretKey) {
      this.stripe = new Stripe(secretKey, { apiVersion: '2025-02-24.acacia' });
    }
  }

  // ─── Booking Slots (operator-facing) ───────────────────────────────────

  async listSlots(token: string, operatorId: string, query: SlotQueryDto) {
    const client = this.supabase.createClient(token);
    let q = client.from('booking_slots').select('*').eq('operator_id', operatorId);

    if (query.from_date) q = q.gte('trip_date', query.from_date);
    if (query.to_date) q = q.lte('trip_date', query.to_date);

    return assertNoError(await q.order('trip_date', { ascending: true }));
  }

  async createSlot(token: string, userId: string, operatorId: string, dto: CreateBookingSlotDto) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('booking_slots')
        .insert({
          operator_id: operatorId,
          dive_site_id: dto.dive_site_id,
          trip_date: dto.trip_date,
          depart_at: dto.depart_at ?? null,
          boat_id: dto.boat_id ?? null,
          price_cents: dto.price_cents,
          currency: dto.currency ?? 'eur',
          max_capacity: dto.max_capacity,
          description: dto.description ?? null,
          created_by: userId,
        })
        .select('*')
        .single(),
    );
  }

  async updateSlot(token: string, operatorId: string, slotId: string, dto: UpdateBookingSlotDto) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('booking_slots')
        .update({
          ...dto,
          updated_at: new Date().toISOString(),
        })
        .eq('id', slotId)
        .eq('operator_id', operatorId)
        .select('*')
        .single(),
    );
  }

  async deleteSlot(token: string, operatorId: string, slotId: string) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('booking_slots')
        .delete()
        .eq('id', slotId)
        .eq('operator_id', operatorId),
    );
  }

  // ─── Public slot browsing (diver-facing) ────────────────────────────────

  async browseSlots(token: string | null, query: SlotQueryDto) {
    const client = this.supabase.createClient(token ?? '');
    const fromDate = query.from_date ?? new Date().toISOString().split('T')[0];
    let q = client
      .from('booking_slots')
      .select('*, operator:operators(id, slug, name), dive_site:dive_sites(id, name, slug, location)')
      .eq('is_active', true)
      .gte('trip_date', fromDate);

    if (query.to_date) q = q.lte('trip_date', query.to_date);
    if (query.lat != null && query.lng != null) {
      const radius = query.radius_km ?? 100;
      q = q.not('dive_site_id', 'is', null);
    }

    return assertNoError(
      await q.order('trip_date', { ascending: true }).order('depart_at', { ascending: true }),
    );
  }

  // ─── Bookings (diver-facing) ────────────────────────────────────────────

  async createBooking(token: string, userId: string, dto: CreateBookingDto) {
    const client = this.supabase.createClient(token);

    // Fetch slot with operator_id
    const slot = await client
      .from('booking_slots')
      .select('*, operator:operators!inner(id)')
      .eq('id', dto.slot_id)
      .single();

    if (slot.error || !slot.data) throw new NotFoundException('Slot not found');

    const slotData = slot.data as Record<string, unknown>;
    const operatorId = (slotData['operator'] as Record<string, unknown>)?.['id'] as string;

    // Call the SECURITY DEFINER function
    const { data, error } = await client.rpc('book_slot', {
      p_slot_id: dto.slot_id,
      p_user_id: userId,
      p_operator_id: operatorId,
      p_diver_name: dto.diver_name ?? null,
      p_diver_email: dto.diver_email ?? null,
      p_diver_phone: dto.diver_phone ?? null,
    });

    if (error) throw new BadRequestException(error.message);

    const result = data as { error?: string; booking_id?: string; price_cents?: number };
    if (result.error) throw new BadRequestException(result.error);

    // Create Stripe PaymentIntent
    let stripePi: { client_secret: string; id: string } | null = null;
    if (this.stripe && result.price_cents && result.price_cents > 0) {
      try {
        const pi = await this.stripe.paymentIntents.create({
          amount: result.price_cents,
          currency: (slotData['currency'] as string) ?? 'eur',
          metadata: {
            booking_id: result.booking_id!,
            slot_id: dto.slot_id,
          },
          automatic_payment_methods: { enabled: true },
        });
        stripePi = { client_secret: pi.client_secret!, id: pi.id };
      } catch (err) {
        this.logger.error(`Stripe PI creation failed: ${(err as Error).message}`);
      }
    }
    // Free slots (price 0) are confirmed inline by book_slot (migration 048);
    // paid slots are confirmed by the Stripe webhook via confirm_booking,
    // which is now service-role only. The API never confirms payment itself.

    return { booking_id: result.booking_id, price_cents: result.price_cents, stripe: stripePi };
  }

  async listMyBookings(token: string, userId: string) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('bookings')
        .select('*, slot:booking_slots(*), operator:operators(id, slug, name)')
        .eq('user_id', userId)
        .order('created_at', { ascending: false }),
    );
  }

  async getBooking(token: string, userId: string, bookingId: string) {
    const client = this.supabase.createClient(token);
    const data = assertNoError(
      await client
        .from('bookings')
        .select('*, slot:booking_slots(*), operator:operators(id, slug, name)')
        .eq('id', bookingId)
        .maybeSingle(),
    );
    if (!data) throw new NotFoundException('Booking not found');

    // Only the booking owner or operator members can view
    const record = data as Record<string, unknown>;
    if (record.user_id !== userId) {
      const isOpMember = await client
        .from('operator_users')
        .select('id')
        .eq('operator_id', record.operator_id)
        .eq('user_id', userId)
        .maybeSingle();
      if (isOpMember.error || !isOpMember.data) {
        throw new NotFoundException('Booking not found');
      }
    }

    return data;
  }

  async cancelBooking(token: string, userId: string, bookingId: string) {
    const client = this.supabase.createClient(token);
    const { data, error } = await client.rpc('cancel_booking', {
      p_booking_id: bookingId,
    });
    if (error) throw new BadRequestException(error.message);
    const result = data as { error?: string };
    if (result.error) throw new BadRequestException(result.error);
    return { success: true };
  }
}
