import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { SightingsService } from './sightings.service';
import { SupabaseService } from '../database/supabase.service';

describe('SightingsService', () => {
  let service: SightingsService;
  let supabase: jest.Mocked<
    Pick<SupabaseService, 'createClient' | 'anonClient' | 'serviceRole'>
  >;

  const mockSighting = {
    id: 'sig-1',
    user_id: 'user-1',
    dive_site_id: 'site-1',
    species_id: 'sp-1',
    dive_log_id: null,
    observed_at: '2024-06-01T10:00:00Z',
    depth_m: 12,
    water_temp_c: 24,
    visibility_m: 20,
    count: 2,
    behavior_tags: ['resting'],
    photo_urls: ['https://cdn.example/1.jpg'],
    confidence_level: 'certain',
    verified_by: 'expert-1',
    verified_at: '2024-06-02T00:00:00Z',
    notes: null,
    location: null,
    source: 'user',
    external_id: null,
    created_at: '2024-06-01T10:00:00Z',
    updated_at: '2024-06-01T10:00:00Z',
  };

  const chain = (result: unknown) => {
    const builder: Record<string, unknown> = {};
    for (const method of [
      'select',
      'eq',
      'gte',
      'not',
      'order',
      'range',
      'insert',
      'update',
      'delete',
      'maybeSingle',
      'single',
    ]) {
      builder[method] = jest.fn().mockReturnValue(builder);
    }
    builder.order = jest.fn().mockResolvedValue(result);
    builder.single = jest.fn().mockResolvedValue(result);
    builder.maybeSingle = jest.fn().mockResolvedValue(result);
    Object.assign(builder, {
      then: (resolve: (v: unknown) => void) => Promise.resolve(result).then(resolve),
    });
    return builder;
  };

  beforeEach(() => {
    supabase = {
      createClient: jest.fn(),
      anonClient: jest.fn(),
      serviceRole: jest.fn(),
    };
    service = new SightingsService(supabase as unknown as SupabaseService);
  });

  it('creates a sighting for the authenticated user', async () => {
    const builder = chain({ data: mockSighting, error: null });
    supabase.createClient.mockReturnValue({
      from: jest.fn().mockReturnValue(builder),
    } as never);

    const result = await service.create('token', 'user-1', {
      dive_site_id: 'site-1',
      species_id: 'sp-1',
      observed_at: '2024-06-01T10:00:00Z',
      count: 2,
    });

    expect(result.id).toBe('sig-1');
    expect(supabase.createClient).toHaveBeenCalledWith('token');
  });

  it('throws when sighting is not found', async () => {
    const builder = chain({ data: null, error: null });
    supabase.anonClient.mockReturnValue({
      from: jest.fn().mockReturnValue(builder),
    } as never);

    await expect(service.getById(undefined, 'missing')).rejects.toThrow(NotFoundException);
  });

  it('rejects self-verification', async () => {
    const unverified = { ...mockSighting, verified_by: null, verified_at: null };
    const builder = chain({
      data: unverified,
      error: null,
    });
    supabase.createClient.mockReturnValue({
      from: jest.fn().mockReturnValue(builder),
    } as never);

    await expect(service.verify('token', 'user-1', 'sig-1')).rejects.toThrow(ForbiddenException);
  });

  it('verifies a sighting', async () => {
    const unverified = { ...mockSighting, verified_by: null, verified_at: null };
    const verified = { ...unverified, verified_by: 'expert-1', verified_at: '2024-06-02T00:00:00Z' };
    const builder: Record<string, jest.Mock> = {
      select: jest.fn().mockReturnThis(),
      eq: jest.fn().mockReturnThis(),
      update: jest.fn().mockReturnThis(),
      maybeSingle: jest.fn().mockResolvedValue({ data: unverified, error: null }),
      single: jest.fn().mockResolvedValue({ data: verified, error: null }),
    };
    supabase.createClient.mockReturnValue({
      from: jest.fn().mockReturnValue(builder),
    } as never);

    const result = await service.verify('token', 'expert-1', 'sig-1');

    expect(result.verified_by).toBe('expert-1');
  });
});
