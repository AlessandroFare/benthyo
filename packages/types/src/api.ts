import type {
  AccessType,
  ConfidenceLevel,
  CurrentStrength,
  GasMix,
  SiteDifficulty,
  SiteType,
} from './enums';
import type {
  Badge,
  DiveLog,
  DiveSite,
  Operator,
  Sighting,
  Species,
  UserProfile,
  Uuid,
} from './entities';

/** Standard paginated list response envelope. */
export interface PaginationMeta {
  page: number;
  page_size: number;
  total: number;
  total_pages: number;
  has_next: boolean;
  has_prev: boolean;
}

export interface Paginated<T> {
  data: T[];
  meta: PaginationMeta;
}

export interface PaginationQuery {
  page?: number;
  page_size?: number;
}

/** Standard API error shape returned by NestJS and Edge Functions. */
export interface ApiError {
  message: string;
  statusCode: number;
  code?: string;
  details?: Record<string, unknown>;
  timestamp?: string;
  path?: string;
}

export interface ApiSuccess<T> {
  data: T;
}

/** Query params for listing dive sites. */
export interface ListDiveSitesQuery extends PaginationQuery {
  country_code?: string;
  difficulty?: SiteDifficulty;
  site_type?: SiteType;
  access_type?: AccessType;
  verified?: boolean;
  q?: string;
  lat?: number;
  lng?: number;
  radius_km?: number;
}

/** Query params for listing species. */
export interface ListSpeciesQuery extends PaginationQuery {
  q?: string;
  family?: string;
  class_name?: string;
  conservation_status?: string;
}

/** Query params for listing sightings. */
export interface ListSightingsQuery extends PaginationQuery {
  dive_site_id?: Uuid;
  species_id?: Uuid;
  user_id?: Uuid;
  verified?: boolean;
  from?: string;
  to?: string;
}

/** Create dive site DTO. */
export interface CreateDiveSiteDto {
  name: string;
  slug: string;
  description?: string;
  lat: number;
  lng: number;
  country_code: string;
  region?: string;
  depth_min: number;
  depth_max: number;
  difficulty: SiteDifficulty;
  site_type: SiteType;
  access_type: AccessType;
  metadata?: Record<string, unknown>;
}

/** Update dive site DTO. */
export type UpdateDiveSiteDto = Partial<Omit<CreateDiveSiteDto, 'slug'>>;

/** Create species DTO. */
export interface CreateSpeciesDto {
  scientific_name: string;
  common_name?: string;
  common_name_it?: string;
  common_name_es?: string;
  family?: string;
  genus?: string;
  inat_taxon_id?: number;
  worms_id?: number;
  gbif_taxon_key?: number;
  description?: string;
  max_depth_m?: number;
  min_depth_m?: number;
  typical_length_cm?: number;
  conservation_status?: string;
  image_url?: string;
  metadata?: Record<string, unknown>;
}

/** Create dive log DTO. */
export interface CreateDiveLogDto {
  dive_site_id?: Uuid;
  operator_id?: Uuid;
  dive_date: string;
  dive_number?: number;
  entry_time?: string;
  exit_time?: string;
  max_depth_m: number;
  avg_depth_m?: number;
  duration_min: number;
  water_temp_surface_c?: number;
  water_temp_bottom_c?: number;
  visibility_m?: number;
  current_strength?: CurrentStrength;
  tank_start_bar?: number;
  tank_end_bar?: number;
  tank_size_l?: number;
  gas_mix?: GasMix;
  buddy_name?: string;
  notes?: string;
  rating?: number;
}

/** Create sighting DTO. */
export interface CreateSightingDto {
  dive_site_id: Uuid;
  species_id: Uuid;
  dive_log_id?: Uuid;
  observed_at: string;
  depth_m?: number;
  water_temp_c?: number;
  visibility_m?: number;
  count?: number;
  behavior_tags?: string[];
  photo_urls?: string[];
  confidence_level?: ConfidenceLevel;
  notes?: string;
  lat?: number;
  lng?: number;
}

/** Update user profile DTO. */
export interface UpdateUserProfileDto {
  full_name?: string;
  avatar_url?: string;
  bio?: string;
  certification_level?: UserProfile['certification_level'];
  certification_agency?: UserProfile['certification_agency'];
}

/** Verify sighting DTO (expert workflow). */
export interface VerifySightingDto {
  confidence_level?: ConfidenceLevel;
  notes?: string;
}

/** Darwin Core export request. */
export interface DarwinCoreExportQuery {
  from?: string;
  to?: string;
  country_code?: string;
  verified_only?: boolean;
  format?: 'json' | 'csv' | 'dwca';
}

/** Weekly digest trigger payload. */
export interface WeeklyDigestPayload {
  user_id?: Uuid;
  dry_run?: boolean;
  week_start?: string;
}

/** Badge award notification payload. */
export interface BadgeAwardedEvent {
  user_id: Uuid;
  badge: Pick<Badge, 'id' | 'code' | 'name' | 'tier'>;
  earned_at: string;
  context_json: Record<string, unknown>;
}

/** Response DTOs with relations. */
export interface DiveSiteDetail extends DiveSite {
  species_count?: number;
  sighting_count?: number;
}

export interface SightingWithDetails extends Sighting {
  dive_site: Pick<DiveSite, 'id' | 'name' | 'slug' | 'region'> | null;
  species: Pick<Species, 'id' | 'scientific_name' | 'common_name' | 'image_url'> | null;
  user: Pick<UserProfile, 'id' | 'username' | 'avatar_url'> | null;
}

export interface DiveLogWithDetails extends DiveLog {
  dive_site: Pick<DiveSite, 'id' | 'name' | 'slug'> | null;
  operator: Pick<Operator, 'id' | 'name' | 'slug'> | null;
  sightings?: Sighting[];
}

/** Dashboard analytics snapshot. */
export interface DashboardKpis {
  total_sites: number;
  total_species: number;
  total_sightings: number;
  total_customers: number;
  sightings_this_month: number;
  sighting_change_pct: number;
  top_site: { id: Uuid; name: string; sighting_count: number } | null;
  top_species: { id: Uuid; name: string; sighting_count: number } | null;
}

export interface TimeSeriesPoint {
  label: string;
  value: number;
}

export interface AnalyticsSnapshot {
  kpi: DashboardKpis;
  sightings_by_month: TimeSeriesPoint[];
  sightings_by_site: TimeSeriesPoint[];
  species_by_family: TimeSeriesPoint[];
}

/** ETL job status returned by GitHub Actions workflows. */
export interface EtlJobResult {
  source: 'gbif' | 'obis' | 'worms' | 'overpass';
  started_at: string;
  finished_at: string;
  records_processed: number;
  records_upserted: number;
  records_skipped: number;
  errors: string[];
}

/** Helper to build pagination meta from query + total count. */
export function buildPaginationMeta(
  page: number,
  pageSize: number,
  total: number,
): PaginationMeta {
  const totalPages = Math.max(1, Math.ceil(total / pageSize));
  return {
    page,
    page_size: pageSize,
    total,
    total_pages: totalPages,
    has_next: page < totalPages,
    has_prev: page > 1,
  };
}
