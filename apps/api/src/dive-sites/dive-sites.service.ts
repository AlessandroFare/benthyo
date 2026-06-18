import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { DiveSite, Sighting } from '../database/database.types';
import { assertNoError } from '../common/utils/supabase-error.util';
import { paginated, PaginatedResult } from '../common/dto/pagination.dto';
import { parseLocation, toGeoJsonPoint } from '../common/utils/geo.util';
import {
  CreateDiveSiteDto,
  ListDiveSitesDto,
  ListSiteSightingsDto,
  NearbyDiveSitesDto,
  SearchDiveSitesDto,
  UpdateDiveSiteDto,
} from './dto/dive-site.dto';

export interface DiveSiteWithCoords extends Omit<DiveSite, 'location'> {
  location: ReturnType<typeof parseLocation>;
}

export interface NearbyDiveSite {
  id: string;
  name: string;
  slug: string;
  country_code: string;
  region: string | null;
  distance_m: number;
}

export interface SpeciesAtSite {
  species_id: string;
  scientific_name: string;
  common_name: string | null;
  common_name_it: string | null;
  common_name_es: string | null;
  image_url: string | null;
  conservation_status: string | null;
  sighting_count: number;
  last_seen_at: string | null;
  avg_depth_m: number | null;
}

@Injectable()
export class DiveSitesService {
  constructor(private readonly supabase: SupabaseService) {}

  private enrichSite(site: DiveSite): DiveSiteWithCoords {
    return {
      ...site,
      location: parseLocation(site.location as unknown as string),
    };
  }

  async list(
    token: string | undefined,
    query: ListDiveSitesDto,
  ): Promise<PaginatedResult<DiveSiteWithCoords>> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    let builder = client.from('dive_sites').select('*', { count: 'exact' });

    if (query.country_code) builder = builder.eq('country_code', query.country_code);
    if (query.difficulty) builder = builder.eq('difficulty', query.difficulty);
    if (query.site_type) builder = builder.eq('site_type', query.site_type);
    if (query.access_type) builder = builder.eq('access_type', query.access_type);
    if (query.verified !== undefined) builder = builder.eq('verified', query.verified);
    if (query.region) builder = builder.ilike('region', `%${query.region}%`);

    const result = await builder
      .order('name')
      .range(query.offset, query.offset + query.limit - 1);

    if (result.error) {
      assertNoError(result);
    }

    const data = ((result.data ?? []) as DiveSite[]).map((s) => this.enrichSite(s));
    return paginated(data, result.count ?? data.length, query.page, query.limit);
  }

  async nearby(
    token: string | undefined,
    query: NearbyDiveSitesDto,
  ): Promise<NearbyDiveSite[]> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    return assertNoError(
      await client.rpc('nearby_dive_sites', {
        p_lat: query.lat,
        p_lng: query.lng,
        p_radius_km: query.radius_km,
      }),
    ) as NearbyDiveSite[];
  }

  async search(
    token: string | undefined,
    query: SearchDiveSitesDto,
  ): Promise<PaginatedResult<DiveSiteWithCoords>> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    const result = await client
      .from('dive_sites')
      .select('*', { count: 'exact' })
      .textSearch('search_tsv', query.q, { type: 'websearch', config: 'simple' })
      .order('name')
      .range(query.offset, query.offset + query.limit - 1);

    if (result.error) {
      assertNoError(result);
    }

    const data = ((result.data ?? []) as DiveSite[]).map((s) => this.enrichSite(s));
    return paginated(data, result.count ?? data.length, query.page, query.limit);
  }

  async getBySlug(token: string | undefined, slug: string): Promise<DiveSiteWithCoords> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    const site = assertNoError(
      await client.from('dive_sites').select('*').eq('slug', slug).maybeSingle(),
    );

    if (!site) {
      throw new NotFoundException(`Dive site "${slug}" not found`);
    }

    return this.enrichSite(site as DiveSite);
  }

  async getById(token: string | undefined, id: string): Promise<DiveSiteWithCoords> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    const site = assertNoError(
      await client.from('dive_sites').select('*').eq('id', id).maybeSingle(),
    );

    if (!site) {
      throw new NotFoundException(`Dive site not found`);
    }

    return this.enrichSite(site as DiveSite);
  }

  async create(token: string, userId: string, dto: CreateDiveSiteDto): Promise<DiveSiteWithCoords> {
    const client = this.supabase.createClient(token);

    const row = {
      name: dto.name,
      slug: dto.slug,
      description: dto.description ?? null,
      location: toGeoJsonPoint(dto.lat, dto.lng),
      country_code: dto.country_code,
      region: dto.region ?? null,
      depth_min: dto.depth_min,
      depth_max: dto.depth_max,
      difficulty: dto.difficulty,
      site_type: dto.site_type,
      access_type: dto.access_type,
      created_by: userId,
      metadata: dto.metadata ?? {},
    };

    const site = assertNoError(
      await client.from('dive_sites').insert(row).select('*').single(),
    ) as DiveSite;

    return this.enrichSite(site);
  }

  async update(token: string, id: string, dto: UpdateDiveSiteDto): Promise<DiveSiteWithCoords> {
    const client = this.supabase.createClient(token);

    const patch: Record<string, unknown> = { ...dto };
    if (dto.lat !== undefined && dto.lng !== undefined) {
      patch.location = toGeoJsonPoint(dto.lat, dto.lng);
      delete patch.lat;
      delete patch.lng;
    } else {
      delete patch.lat;
      delete patch.lng;
    }

    const site = assertNoError(
      await client.from('dive_sites').update(patch).eq('id', id).select('*').single(),
    ) as DiveSite;

    return this.enrichSite(site);
  }

  async remove(token: string, id: string): Promise<{ deleted: true }> {
    const client = this.supabase.createClient(token);
    assertNoError(await client.from('dive_sites').delete().eq('id', id));
    return { deleted: true };
  }

  async getSpecies(token: string | undefined, siteId: string): Promise<SpeciesAtSite[]> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    return assertNoError(
      await client.rpc('species_at_site', { p_site_id: siteId }),
    ) as SpeciesAtSite[];
  }

  async getSightings(
    token: string | undefined,
    siteId: string,
    query: ListSiteSightingsDto,
  ): Promise<PaginatedResult<Sighting>> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    let builder = client
      .from('sightings')
      .select('*', { count: 'exact' })
      .eq('dive_site_id', siteId);

    if (query.species_id) {
      builder = builder.eq('species_id', query.species_id);
    }

    const result = await builder
      .order('observed_at', { ascending: false })
      .range(query.offset, query.offset + query.limit - 1);

    if (result.error) {
      assertNoError(result);
    }

    return paginated(
      (result.data ?? []) as Sighting[],
      result.count ?? 0,
      query.page,
      query.limit,
    );
  }
}
