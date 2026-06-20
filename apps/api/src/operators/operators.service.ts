import { Injectable, NotFoundException, ForbiddenException } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { Operator, OperatorDiveSite, OperatorUser } from '../database/database.types';
import { assertNoError } from '../common/utils/supabase-error.util';
import { paginated, PaginatedResult } from '../common/dto/pagination.dto';
import { toGeoJsonPoint } from '../common/utils/geo.util';

/**
 * Per-tier resource caps (README "Subscriptions & billing"). Enforced
 * server-side here; the DB trigger added in migration 045 is the
 * second line of defense for direct PostgREST writes.
 */
const TIER_SITE_LIMIT: Record<string, number> = { free: 3, starter: 10, pro: 100 };
const TIER_TEAM_LIMIT: Record<string, number> = { free: 1, starter: 5, pro: 20 };
import {
  CreateOperatorDto,
  LinkDiveSiteDto,
  ListOperatorCustomersDto,
  ListOperatorSpeciesDto,
  ListOperatorsDto,
  OperatorAnalyticsQueryDto,
  UpdateOperatorDto,
  InviteOperatorUserDto,
} from './dto/operator.dto';

export interface OperatorKpis {
  total_customers: number;
  dives_in_window: number;
  active_sites: number;
  top_species: Array<{
    species_id: string;
    common_name: string | null;
    scientific_name: string;
    sighting_count: number;
  }> | null;
}

export interface OperatorDivesByMonth {
  month: string;
  count: number;
}

@Injectable()
export class OperatorsService {
  constructor(private readonly supabase: SupabaseService) {}

  async list(
    token: string | undefined,
    query: ListOperatorsDto,
  ): Promise<PaginatedResult<Operator>> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    let builder = client.from('operators').select('*', { count: 'exact' });

    if (query.country_code) builder = builder.eq('country_code', query.country_code);
    if (query.operator_type) builder = builder.eq('operator_type', query.operator_type);

    const result = await builder
      .order('name')
      .range(query.offset, query.offset + query.limit - 1);

    if (result.error) {
      assertNoError(result);
    }

    return paginated(
      (result.data ?? []) as Operator[],
      result.count ?? 0,
      query.page,
      query.limit,
    );
  }

  async getBySlug(token: string | undefined, slug: string): Promise<Operator> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    const operator = assertNoError(
      await client.from('operators').select('*').eq('slug', slug).maybeSingle(),
    );

    if (!operator) {
      throw new NotFoundException(`Operator "${slug}" not found`);
    }

    return operator as Operator;
  }

  async create(token: string, userId: string, dto: CreateOperatorDto): Promise<Operator> {
    const client = this.supabase.createClient(token);

    const row: Record<string, unknown> = {
      name: dto.name,
      slug: dto.slug,
      description: dto.description ?? null,
      website: dto.website ?? null,
      email: dto.email ?? null,
      phone: dto.phone ?? null,
      address: dto.address ?? null,
      country_code: dto.country_code ?? null,
      operator_type: dto.operator_type,
    };

    if (dto.lat !== undefined && dto.lng !== undefined) {
      row.location = toGeoJsonPoint(dto.lat, dto.lng);
    }

    const operator = assertNoError(
      await client.from('operators').insert(row).select('*').single(),
    ) as Operator;

    assertNoError(
      await client.from('operator_users').insert({
        operator_id: operator.id,
        user_id: userId,
        role: 'owner',
        accepted_at: new Date().toISOString(),
      }),
    );

    return operator;
  }

  async update(token: string, operatorId: string, dto: UpdateOperatorDto): Promise<Operator> {
    const client = this.supabase.createClient(token);

    return assertNoError(
      await client
        .from('operators')
        .update(dto)
        .eq('id', operatorId)
        .select('*')
        .single(),
    ) as Operator;
  }

  async getMembers(token: string, operatorId: string): Promise<OperatorUser[]> {
    const client = this.supabase.createClient(token);

    return assertNoError(
      await client
        .from('operator_users')
        .select('*')
        .eq('operator_id', operatorId)
        .order('invited_at'),
    ) as OperatorUser[];
  }

  /**
   * Enforce a per-tier row cap before an INSERT. Reads the operator's
   * current tier and the live row count for `table`; throws 403 when the
   * new row would exceed the cap. RLS already scopes the count to the
   * caller's operator.
   */
  private async assertUnderTierLimit(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    client: any,
    operatorId: string,
    table: 'operator_dive_sites' | 'operator_users',
    limits: Record<string, number>,
    label: string,
  ): Promise<void> {
    const op = assertNoError(
      await client
        .from('operators')
        .select('subscription_tier')
        .eq('id', operatorId)
        .maybeSingle(),
    ) as { subscription_tier: string | null } | null;
    const tier = (op?.subscription_tier ?? 'free') as string;
    const cap = limits[tier] ?? limits['free'];

    const { count, error } = await client
      .from(table)
      .select('*', { count: 'exact', head: true })
      .eq('operator_id', operatorId);
    if (error) assertNoError({ data: null, error });

    if ((count ?? 0) >= cap) {
      throw new ForbiddenException(
        `${label} limit reached for the ${tier} tier (${cap}). Upgrade to add more.`,
      );
    }
  }

  async inviteMember(
    token: string,
    operatorId: string,
    dto: InviteOperatorUserDto,
  ): Promise<OperatorUser> {
    const client = this.supabase.createClient(token);

    await this.assertUnderTierLimit(
      client,
      operatorId,
      'operator_users',
      TIER_TEAM_LIMIT,
      'Team member',
    );

    return assertNoError(
      await client
        .from('operator_users')
        .insert({
          operator_id: operatorId,
          user_id: dto.user_id,
          role: dto.role,
        })
        .select('*')
        .single(),
    ) as OperatorUser;
  }

  async getSites(token: string, operatorId: string): Promise<Record<string, unknown>[]> {
    const client = this.supabase.createClient(token);
    const links = assertNoError(
      await client
        .from('operator_dive_sites')
        .select('operator_id, dive_site_id, is_primary, added_at, dive_sites(*)')
        .eq('operator_id', operatorId)
        .order('added_at', { ascending: false }),
    ) as Array<Record<string, unknown>>;
    const enriched: Record<string, unknown>[] = [];
    for (const link of links) {
      const site = link.dive_sites as Record<string, unknown>;
      const stats = assertNoError(
        await client
          .from('species_dive_site_stats')
          .select('sighting_count')
          .eq('dive_site_id', link.dive_site_id as string),
      ) as Array<{ sighting_count: number }>;
      const sightingCount = stats.reduce((sum, row) => sum + row.sighting_count, 0);
      enriched.push({
        id: link.dive_site_id,
        dive_site_id: link.dive_site_id,
        name: site.name,
        region: site.region,
        country_code: site.country_code,
        depth_max: site.depth_max,
        difficulty: site.difficulty,
        is_primary: link.is_primary,
        sighting_count: sightingCount,
        added_at: link.added_at,
      });
    }
    return enriched;
  }

  async linkSite(
    token: string,
    operatorId: string,
    dto: LinkDiveSiteDto,
  ): Promise<OperatorDiveSite> {
    const client = this.supabase.createClient(token);

    await this.assertUnderTierLimit(
      client,
      operatorId,
      'operator_dive_sites',
      TIER_SITE_LIMIT,
      'Dive site',
    );

    return assertNoError(
      await client
        .from('operator_dive_sites')
        .insert({
          operator_id: operatorId,
          dive_site_id: dto.dive_site_id,
          is_primary: dto.is_primary,
        })
        .select('*')
        .single(),
    ) as OperatorDiveSite;
  }

  async unlinkSite(
    token: string,
    operatorId: string,
    diveSiteId: string,
  ): Promise<{ deleted: true }> {
    const client = this.supabase.createClient(token);

    assertNoError(
      await client
        .from('operator_dive_sites')
        .delete()
        .eq('operator_id', operatorId)
        .eq('dive_site_id', diveSiteId),
    );

    return { deleted: true };
  }

  async getKpis(
    token: string,
    operatorId: string,
    query: OperatorAnalyticsQueryDto,
  ): Promise<OperatorKpis> {
    const client = this.supabase.createClient(token);

    const kpis = assertNoError(
      await client.rpc('operator_kpis', {
        p_operator_id: operatorId,
        p_window_days: query.window_days,
      }),
    );

    return kpis as OperatorKpis;
  }

  async getDivesByMonth(
    token: string,
    operatorId: string,
  ): Promise<OperatorDivesByMonth[]> {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client.rpc('operator_dives_by_month', {
        p_operator_id: operatorId,
      }),
    ) as OperatorDivesByMonth[];
  }

  async getMyOperator(token: string, userId: string): Promise<Operator & { role: string }> {
    const client = this.supabase.createClient(token);
    const membership = assertNoError(
      await client
        .from('operator_users')
        .select('role, operators(*)')
        .eq('user_id', userId)
        .limit(1)
        .maybeSingle(),
    ) as { role: string; operators: Operator } | null;
    if (!membership?.operators) {
      throw new NotFoundException('No operator profile linked to this account');
    }
    return { ...membership.operators, role: membership.role };
  }

  /**
   * Soft-delete the caller's primary operator. Goes through the
   * SECURITY DEFINER `soft_delete_row` RPC so the column-level RLS
   * policy on operators doesn't block the write. The caller's
   * operator-role guard must already have verified `role = owner`.
   */
  async softDeleteMyOperator(
    token: string,
    operatorId: string,
    reason?: string,
  ): Promise<{ soft_deleted: true; operator_id: string }> {
    const client = this.supabase.createClient(token);
    const { error } = await client.rpc('soft_delete_row', {
      p_table: 'operators',
      p_id: operatorId,
      p_reason: reason ?? 'user_requested',
    });
    assertNoError({ data: null, error });
    return { soft_deleted: true, operator_id: operatorId };
  }

  async getDashboardKpis(
    token: string,
    operatorId: string,
    windowDays = 30,
  ): Promise<Record<string, unknown>> {
    const client = this.supabase.createClient(token);
    const kpis = await this.getKpis(token, operatorId, { window_days: windowDays });
    const topSpecies = kpis.top_species?.[0];
    const divesBySite = assertNoError(
      await client.rpc('operator_dives_by_site', { p_operator_id: operatorId }),
    ) as Array<{ site_id: string; name: string; dive_count: number }>;
    const topSite = divesBySite?.[0];
    const siteRows = assertNoError(
      await client.from('operator_dive_sites').select('dive_site_id').eq('operator_id', operatorId),
    ) as Array<{ dive_site_id: string }>;
    let totalSightings = 0;
    if (siteRows.length > 0) {
      const sightingResult = await client
        .from('sightings')
        .select('id', { count: 'exact', head: true })
        .in(
          'dive_site_id',
          siteRows.map((r) => r.dive_site_id),
        );
      totalSightings = sightingResult.count ?? 0;
    }
    return {
      total_sites: kpis.active_sites,
      total_species: kpis.top_species?.length ?? 0,
      total_sightings: totalSightings,
      total_customers: kpis.total_customers,
      sightings_this_month: kpis.dives_in_window,
      sighting_change_pct: 0,
      top_site: topSite
        ? { id: topSite.site_id, name: topSite.name, sighting_count: topSite.dive_count }
        : null,
      top_species: topSpecies
        ? {
            id: topSpecies.species_id,
            name: topSpecies.common_name ?? topSpecies.scientific_name,
            sighting_count: topSpecies.sighting_count,
          }
        : null,
    };
  }

  async getDashboardCharts(
    token: string,
    operatorId: string,
  ): Promise<Record<string, unknown>> {
    const client = this.supabase.createClient(token);
    const [byMonth, bySite] = await Promise.all([
      this.getDivesByMonth(token, operatorId),
      assertNoError(
        await client.rpc('operator_dives_by_site', { p_operator_id: operatorId }),
      ) as Array<{ name: string; dive_count: number }>,
    ]);
    return {
      sightings_trend: byMonth.map((row) => ({
        label: row.month.slice(0, 7),
        value: row.count,
      })),
      dives_by_site: (bySite ?? []).map((row) => ({
        label: row.name,
        value: row.dive_count,
      })),
    };
  }

  async getAnalyticsBundle(
    token: string,
    operatorId: string,
  ): Promise<Record<string, unknown>> {
    const client = this.supabase.createClient(token);
    const [heatmap, diversity, depthHistogram, retention] = await Promise.all([
      assertNoError(
        await client.rpc('operator_activity_heatmap', { p_operator_id: operatorId }),
      ),
      assertNoError(
        await client.rpc('operator_species_diversity', { p_operator_id: operatorId }),
      ),
      assertNoError(
        await client.rpc('operator_depth_histogram', { p_operator_id: operatorId }),
      ),
      assertNoError(
        await client.rpc('operator_customer_retention', { p_operator_id: operatorId }),
      ),
    ]);
    return {
      heatmap: heatmap ?? [],
      diversity: diversity ?? [],
      depth_histogram: (depthHistogram ?? []).filter(
        (row: { range: string }) => row.range !== 'unknown',
      ),
      retention: retention ?? [],
    };
  }

  async getCustomers(
    token: string,
    operatorId: string,
    query: ListOperatorCustomersDto,
  ): Promise<PaginatedResult<Record<string, unknown>>> {
    const client = this.supabase.createClient(token);
    const rows = assertNoError(
      await client.rpc('operator_customers', {
        p_operator_id: operatorId,
        p_limit: query.limit,
        p_offset: query.offset,
        p_search: query.q ?? null,
      }),
    ) as Array<Record<string, unknown>>;

    const total = rows.length > 0 ? Number(rows[0].total_count ?? 0) : 0;
    const data = rows.map((row) => {
      const fullName = String(row.full_name ?? '');
      const parts = fullName.trim().split(/\s+/);
      const firstName = parts[0] || String(row.username ?? 'Diver');
      const lastName = parts.length > 1 ? parts.slice(1).join(' ') : '';
      return {
        id: row.user_id,
        operator_id: operatorId,
        email: String(row.username ?? ''),
        first_name: firstName,
        last_name: lastName,
        certification_level: row.certification_level ?? null,
        total_dives: Number(row.operator_dive_count ?? 0),
        last_dive_at: row.last_dive_at ?? null,
        tags: [],
        created_at: row.last_dive_at ?? new Date().toISOString(),
        updated_at: row.last_dive_at ?? new Date().toISOString(),
      };
    });

    return paginated(data, total, query.page, query.limit);
  }

  async getSpeciesRanked(
    token: string,
    operatorId: string,
    query: ListOperatorSpeciesDto,
  ): Promise<PaginatedResult<Record<string, unknown>>> {
    const client = this.supabase.createClient(token);
    const rows = assertNoError(
      await client.rpc('operator_species_ranked', {
        p_operator_id: operatorId,
        p_limit: query.limit,
        p_offset: query.offset,
        p_search: query.q ?? null,
      }),
    ) as Array<Record<string, unknown>>;

    const total = rows.length > 0 ? Number(rows[0].total_count ?? 0) : 0;
    const data = rows.map((row) => ({
      id: row.species_id,
      scientific_name: row.scientific_name,
      common_name: row.common_name ?? null,
      family: row.family ?? null,
      sighting_count: Number(row.sighting_count ?? 0),
      site_count: Number(row.site_count ?? 0),
      last_seen_at: row.last_seen_at ?? null,
      conservation_status: row.conservation_status ?? null,
      photo_url: row.image_url ?? null,
    }));

    return paginated(data, total, query.page, query.limit);
  }

  async getRecentActivity(
    token: string,
    operatorId: string,
    limit = 10,
  ): Promise<Array<Record<string, unknown>>> {
    const client = this.supabase.createClient(token);
    const siteRows = assertNoError(
      await client
        .from('operator_dive_sites')
        .select('dive_site_id')
        .eq('operator_id', operatorId),
    ) as Array<{ dive_site_id: string }>;
    const siteIds = siteRows.map((row) => row.dive_site_id);
    if (siteIds.length === 0) {
      return [];
    }
    const logs = assertNoError(
      await client
        .from('dive_logs')
        .select('id, dive_date, users(username)')
        .in('dive_site_id', siteIds)
        .order('dive_date', { ascending: false })
        .limit(limit),
    ) as Array<Record<string, unknown>>;
    return logs.map((log) => ({
      id: log.id,
      type: 'dive',
      title: 'Dive logged',
      description: String((log.users as { username?: string })?.username ?? 'Diver'),
      occurred_at: log.dive_date,
    }));
  }

  /**
   * Today's roster for an operator: scheduled trips with boat, guide, site
   * and booked / checked-in counts. Backed by the operator_today_roster()
   * RPC (SECURITY DEFINER, authz enforced inside the function via
   * is_operator_member). `date` is an optional YYYY-MM-DD override; when
   * omitted the RPC defaults to current_date.
   */
  async getTodayRoster(
    token: string,
    operatorId: string,
    date?: string,
  ): Promise<Array<Record<string, unknown>>> {
    const client = this.supabase.createClient(token);
    const params: Record<string, unknown> = { p_operator_id: operatorId };
    if (date) {
      params.p_date = date;
    }
    const rows = assertNoError(
      await client.rpc('operator_today_roster', params),
    ) as Array<Record<string, unknown>> | null;
    return rows ?? [];
  }
}
