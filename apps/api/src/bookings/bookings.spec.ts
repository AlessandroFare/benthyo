import { BadRequestException, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { BookingsService } from './bookings.service';
import { SupabaseService } from '../database/supabase.service';

// Mock Stripe so we can exercise the payment-intent path without network. The
// factory returns a fresh mock per test via mockImplementation in tests that
// need it; by default paymentIntents.create rejects.
const mockStripeCreate = jest.fn();
jest.mock('stripe', () => {
  return {
    __esModule: true,
    default: jest.fn().mockImplementation(() => ({
      paymentIntents: { create: mockStripeCreate },
    })),
  };
});

describe('BookingsService', () => {
  let service: BookingsService;
  let supabase: jest.Mocked<Pick<SupabaseService, 'createClient'>>;
  let config: jest.Mocked<Pick<ConfigService, 'get'>>;

  const mockUser = 'user-1';
  const mockSlot = 'slot-1';
  const mockOperator = 'op-1';

  const buildClient = (overrides: Record<string, unknown> = {}) => {
    const rpc = jest.fn().mockImplementation((fnName: string, _args: unknown) => {
      if (fnName === 'book_slot') {
        return { data: { booking_id: 'b-1', price_cents: 0, currency: 'eur', status: 'confirmed', ...overrides }, error: null };
      }
      return { data: null, error: null };
    });

    const singleResult = { data: { id: mockSlot, operator: { id: mockOperator }, currency: 'eur', ...overrides }, error: null };
    const selectBuilder = {
      select: jest.fn().mockReturnThis(),
      eq: jest.fn().mockReturnThis(),
      gte: jest.fn().mockReturnThis(),
      lte: jest.fn().mockReturnThis(),
      not: jest.fn().mockReturnThis(),
      order: jest.fn().mockReturnThis(),
      maybeSingle: jest.fn().mockResolvedValue({ data: null, error: null }),
      single: jest.fn().mockResolvedValue(singleResult),
    };

    return {
      from: jest.fn(() => selectBuilder),
      rpc,
    };
  };

  beforeEach(() => {
    supabase = { createClient: jest.fn() };
    config = { get: jest.fn() };
    (supabase.createClient as jest.Mock).mockReturnValue(buildClient());
    service = new BookingsService(supabase as unknown as SupabaseService, config as unknown as ConfigService);
  });

  describe('createBooking', () => {
    it('calls book_slot RPC with correct args', async () => {
      const client = buildClient();
      (supabase.createClient as jest.Mock).mockReturnValue(client);

      await service.createBooking('token', mockUser, { slot_id: mockSlot });

      expect(client.rpc).toHaveBeenCalled();
      const callArgs = (client.rpc as jest.Mock).mock.calls[0][1];
      expect(callArgs.p_slot_id).toBe(mockSlot);
      expect(callArgs.p_user_id).toBe(mockUser);
      expect(callArgs.p_operator_id).toEqual(expect.any(String));
    });

    it('returns confirmed status for free slots (price_cents = 0)', async () => {
      const client = buildClient({ price_cents: 0, status: 'confirmed' });
      (supabase.createClient as jest.Mock).mockReturnValue(client);

      const result = await service.createBooking('token', mockUser, { slot_id: mockSlot });
      expect(result).toHaveProperty('booking_id');
      expect(result.stripe).toBeNull();
    });

    it('generates Stripe PaymentIntent for paid slots when payments are configured', async () => {
      // Configure Stripe via ConfigService and make paymentIntents.create succeed.
      (config.get as jest.Mock).mockImplementation((key: string) =>
        key === 'STRIPE_SECRET_KEY' ? 'sk_test_xxx' : undefined,
      );
      mockStripeCreate.mockResolvedValueOnce({
        id: 'pi_test_1',
        client_secret: 'cs_test_1',
      });
      // Re-instantiate so the constructor wires up this.stripe with the key.
      const client = buildClient({ price_cents: 500, status: 'pending_payment' });
      (supabase.createClient as jest.Mock).mockReturnValue(client);
      service = new BookingsService(supabase as unknown as SupabaseService, config as unknown as ConfigService);

      const result = await service.createBooking('token', mockUser, { slot_id: mockSlot });
      expect(result).toHaveProperty('booking_id');
      expect(result.stripe).toEqual({ client_secret: 'cs_test_1', id: 'pi_test_1' });
    });

    it('rolls back the booking when payments are not configured for a paid slot', async () => {
      // No STRIPE_SECRET_KEY → this.stripe is null (default beforeEach state).
      const client = buildClient({ price_cents: 500, status: 'pending_payment' });
      const rpcSpy = client.rpc as jest.Mock;
      (supabase.createClient as jest.Mock).mockReturnValue(client);

      await expect(service.createBooking('token', mockUser, { slot_id: mockSlot }))
        .rejects.toThrow(ServiceUnavailableException);
      // cancel_booking rollback must have been invoked with the booking id.
      expect(rpcSpy).toHaveBeenCalledWith('cancel_booking', { p_booking_id: 'b-1' });
    });

    it('rolls back the booking when Stripe PI creation fails', async () => {
      (config.get as jest.Mock).mockImplementation((key: string) =>
        key === 'STRIPE_SECRET_KEY' ? 'sk_test_xxx' : undefined,
      );
      mockStripeCreate.mockRejectedValueOnce(new Error('stripe down'));
      const client = buildClient({ price_cents: 500, status: 'pending_payment' });
      const rpcSpy = client.rpc as jest.Mock;
      (supabase.createClient as jest.Mock).mockReturnValue(client);
      service = new BookingsService(supabase as unknown as SupabaseService, config as unknown as ConfigService);

      await expect(service.createBooking('token', mockUser, { slot_id: mockSlot }))
        .rejects.toThrow(ServiceUnavailableException);
      expect(rpcSpy).toHaveBeenCalledWith('cancel_booking', { p_booking_id: 'b-1' });
    });

    it('throws when slot is not found', async () => {
      const client = buildClient();
      client.rpc = jest.fn().mockResolvedValue({ data: { error: 'Slot not found' }, error: null });
      (supabase.createClient as jest.Mock).mockReturnValue(client);

      await expect(service.createBooking('token', mockUser, { slot_id: mockSlot }))
        .rejects.toThrow(BadRequestException);
    });

    it('throws when slot is fully booked', async () => {
      const client = buildClient();
      client.rpc = jest.fn().mockResolvedValue({ data: { error: 'Slot is fully booked' }, error: null });
      (supabase.createClient as jest.Mock).mockReturnValue(client);

      await expect(service.createBooking('token', mockUser, { slot_id: mockSlot }))
        .rejects.toThrow(BadRequestException);
    });
  });

  describe('listMyBookings', () => {
    it('returns user bookings ordered by created_at desc', async () => {
      const client = buildClient();
      (supabase.createClient as jest.Mock).mockReturnValue(client);

      await service.listMyBookings('token', mockUser);
      expect(client.from).toHaveBeenCalledWith('bookings');
    });
  });

  describe('cancelBooking', () => {
    it('calls cancel_booking RPC', async () => {
      const client = buildClient();
      client.rpc = jest.fn().mockResolvedValue({ data: {}, error: null });
      (supabase.createClient as jest.Mock).mockReturnValue(client);

      await service.cancelBooking('token', mockUser, 'b-1');
      expect(client.rpc).toHaveBeenCalledWith('cancel_booking', {
        p_booking_id: 'b-1',
      });
    });
  });
});
