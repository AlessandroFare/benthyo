import { NotFoundException } from '@nestjs/common';
import { DiveSitesService } from './dive-sites.service';
import { SupabaseService } from '../database/supabase.service';
import { ListDiveSitesDto } from './dto/dive-site.dto';

describe('DiveSitesService', () => {
  let service: DiveSitesService;
  let supabase: jest.Mocked<Pick<SupabaseService, 'createClient' | 'anonClient'>>;

  const mockSite = {
    id: 'site-1',
    name: 'Blue Hole',
    slug: 'blue-hole',
    description: null,
    location: 'POINT(25.0 36.0)',
    country_code: 'EG',
    region: 'Dahab',
    depth_min: 5,
    depth_max: 130,
    difficulty: 'advanced',
    site_type: 'wall',
    access_type: 'shore',
    created_by: null,
    verified: true,
    metadata: {},
    created_at: '2024-01-01T00:00:00Z',
    updated_at: '2024-01-01T00:00:00Z',
  };

  const chain = (result: unknown) => {
    const builder: Record<string, unknown> = {};
    const terminal = jest.fn().mockResolvedValue(result);
    for (const method of [
      'select',
      'eq',
      'ilike',
      'order',
      'range',
      'textSearch',
      'insert',
      'update',
      'delete',
      'maybeSingle',
      'single',
    ]) {
      builder[method] = jest.fn().mockReturnValue(builder);
    }
    builder.range = terminal;
    builder.single = terminal;
    builder.maybeSingle = terminal;
    Object.assign(builder, {
      then: (resolve: (v: unknown) => void) => Promise.resolve(result).then(resolve),
    });
    return builder;
  };

  beforeEach(() => {
    supabase = {
      createClient: jest.fn(),
      anonClient: jest.fn(),
    };
    service = new DiveSitesService(supabase as unknown as SupabaseService);
  });

  it('lists dive sites with pagination', async () => {
    const builder = chain({ data: [mockSite], error: null, count: 1 });
    supabase.anonClient.mockReturnValue({ from: jest.fn().mockReturnValue(builder) } as never);

    const query = Object.assign(new ListDiveSitesDto(), { page: 1, limit: 20 });
    const result = await service.list(undefined, query);

    expect(result.data).toHaveLength(1);
    expect(result.data[0].location).toEqual({ lat: 36, lng: 25 });
    expect(result.total).toBe(1);
  });

  it('finds nearby sites via RPC', async () => {
    const rpc = jest.fn().mockResolvedValue({
      data: [{ id: 'site-1', name: 'Blue Hole', slug: 'blue-hole', distance_m: 100 }],
      error: null,
    });
    supabase.anonClient.mockReturnValue({ rpc } as never);

    const result = await service.nearby(undefined, { lat: 36, lng: 25, radius_km: 10 });

    expect(rpc).toHaveBeenCalledWith('nearby_dive_sites', {
      p_lat: 36,
      p_lng: 25,
      p_radius_km: 10,
    });
    expect(result).toHaveLength(1);
  });

  it('throws when slug is not found', async () => {
    const builder = chain({ data: null, error: null });
    supabase.anonClient.mockReturnValue({ from: jest.fn().mockReturnValue(builder) } as never);

    await expect(service.getBySlug(undefined, 'missing')).rejects.toThrow(NotFoundException);
  });

  it('creates a dive site with geo point', async () => {
    const insertBuilder = chain({ data: mockSite, error: null });
    supabase.createClient.mockReturnValue({
      from: jest.fn().mockReturnValue(insertBuilder),
    } as never);

    const result = await service.create('token', 'user-1', {
      name: 'Blue Hole',
      slug: 'blue-hole',
      lat: 36,
      lng: 25,
      country_code: 'EG',
      depth_min: 5,
      depth_max: 130,
      difficulty: 'advanced',
      site_type: 'wall',
      access_type: 'shore',
    });

    expect(supabase.createClient).toHaveBeenCalledWith('token');
    expect(result.slug).toBe('blue-hole');
  });
});
