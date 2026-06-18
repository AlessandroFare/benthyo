import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { Sighting } from '../database/database.types';
import { assertNoError } from '../common/utils/supabase-error.util';
import { paginated, PaginatedResult } from '../common/dto/pagination.dto';
import { toGeoJsonPoint } from '../common/utils/geo.util';
import {
  CreateSightingDto,
  ListSightingsDto,
  UpdateSightingDto,
} from './dto/sighting.dto';

@Injectable()
export class SightingsService {
  constructor(private readonly supabase: SupabaseService) {}

  async list(
    token: string | undefined,
    query: ListSightingsDto,
  ): Promise<PaginatedResult<Sighting>> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    let builder = client.from('sightings').select('*', { count: 'exact' });

    if (query.dive_site_id) builder = builder.eq('dive_site_id', query.dive_site_id);
    if (query.species_id) builder = builder.eq('species_id', query.species_id);
    if (query.user_id) builder = builder.eq('user_id', query.user_id);

    const result = await builder
      .order('observed_at', { ascending: false })
      .range(query.offset, query.offset + query.limit - 1);

    if (result.error) assertNoError(result);

    return paginated(
      (result.data ?? []) as Sighting[],
      result.count ?? 0,
      query.page,
      query.limit,
    );
  }

  async getById(token: string | undefined, id: string): Promise<Sighting> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    const sighting = assertNoError(
      await client.from('sightings').select('*').eq('id', id).maybeSingle(),
    );

    if (!sighting) throw new NotFoundException('Sighting not found');
    return sighting as Sighting;
  }

  async create(token: string, userId: string, dto: CreateSightingDto): Promise<Sighting> {
    const client = this.supabase.createClient(token);

    const row: Record<string, unknown> = {
      user_id: userId,
      dive_site_id: dto.dive_site_id,
      species_id: dto.species_id,
      dive_log_id: dto.dive_log_id ?? null,
      observed_at: dto.observed_at,
      depth_m: dto.depth_m ?? null,
      water_temp_c: dto.water_temp_c ?? null,
      visibility_m: dto.visibility_m ?? null,
      count: dto.count ?? 1,
      behavior_tags: dto.behavior_tags ?? [],
      photo_urls: dto.photo_urls ?? [],
      confidence_level: dto.confidence_level ?? 'likely',
      notes: dto.notes ?? null,
      source: 'user',
    };

    if (dto.lat !== undefined && dto.lng !== undefined) {
      row.location = toGeoJsonPoint(dto.lat, dto.lng);
    }

    const sighting = assertNoError(
      await client.from('sightings').insert(row).select('*').single(),
    ) as Sighting;

    return sighting;
  }

  /**
   * Update a sighting. Scoped to the caller's user_id at the service
   * level — RLS is the second line of defense.
   */
  async update(
    token: string,
    userId: string,
    id: string,
    dto: UpdateSightingDto,
  ): Promise<Sighting> {
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

    const sighting = assertNoError(
      await client
        .from('sightings')
        .update(patch)
        .eq('id', id)
        .eq('user_id', userId)
        .select('*')
        .maybeSingle(),
    );

    if (!sighting) {
      // Either the row doesn't exist or it isn't yours. Same response in
      // both cases so we don't leak existence to non-owners.
      throw new NotFoundException('Sighting not found');
    }
    return sighting as Sighting;
  }

  /**
   * Soft-delete a sighting (the row stays in the database so we can
   * honor GBIF "delete with provenance" semantics and undo a bad
   * restore within 30 days). Scoped to the caller's user_id unless the
   * caller is admin (handled by migration 033's soft_delete_row RPC).
   *
   * The DELETE verb stays for backward compatibility; the underlying
   * behaviour is now soft-delete with a 30-day restore window. Hard
   * delete is available via /v1/admin/purge/:table/:id.
   */
  async remove(token: string, userId: string, id: string, reason?: string): Promise<{ soft_deleted: true; id: string }> {
    const client = this.supabase.createClient(token);

    // Make sure the caller owns the row before asking the RPC to do
    // the soft-delete. This prevents enumeration of other users' rows.
    const owner = await client
      .from('sightings')
      .select('id, user_id')
      .eq('id', id)
      .maybeSingle();
    if (owner.error) assertNoError(owner);
    if (!owner.data) throw new NotFoundException('Sighting not found');
    if (owner.data.user_id !== userId) {
      // Caller is not the owner. Fall through to the admin check
      // (which the RPC enforces via is_app_admin()).
    }

    const { error } = await client.rpc('soft_delete_row', {
      p_table: 'sightings',
      p_id: id,
      p_reason: reason ?? 'user_requested',
    });
    if (error) assertNoError({ data: null, error });
    return { soft_deleted: true, id };
  }

  /**
   * Mark a sighting as verified. Requires the caller to be a taxonomy
   * expert (enforced at the controller via TaxonomyExpertGuard). The
   * service additionally refuses to self-verify — an expert cannot
   * verify their own sightings, which prevents the data-moa t pollution
   * path described in C-3.
   */
  async verify(token: string, verifierId: string, id: string): Promise<Sighting> {
    const client = this.supabase.createClient(token);

    // Reject self-verify.
    const existing = assertNoError(
      await client
        .from('sightings')
        .select('id, user_id, verified_by, verified_at')
        .eq('id', id)
        .maybeSingle(),
    );
    if (!existing) throw new NotFoundException('Sighting not found');
    if (existing.user_id === verifierId) {
      throw new ForbiddenException('You cannot verify your own sightings');
    }
    if (existing.verified_by) {
      throw new ForbiddenException('Sighting is already verified');
    }

    const sighting = assertNoError(
      await client
        .from('sightings')
        .update({
          verified_by: verifierId,
          verified_at: new Date().toISOString(),
          confidence_level: 'certain',
        })
        .eq('id', id)
        .select('*')
        .single(),
    ) as Sighting;

    return sighting;
  }
}
