/**
 * Shared TypeScript types for Benthyo.
 * Mirrors the PostgreSQL schema in supabase/migrations/ and API contracts.
 */

import type {
  AccessType,
  BadgeCriteriaType,
  CertAgency,
  CertLevel,
  ConfidenceLevel,
  ConservationStatus,
  CurrentStrength,
  GasMix,
  OperatorRole,
  OperatorType,
  SightingSource,
  SiteDifficulty,
  SiteType,
  SubscriptionStatus,
  SubscriptionTier,
} from './enums';

/** Branded UUID string used across API contracts. */
export type Uuid = string;

// ── Entity interfaces ─────────────────────────────────────

export interface User {
  id: string;
  username: string;
  full_name: string | null;
  avatar_url: string | null;
  bio: string | null;
  certification_level: CertLevel;
  certification_agency: CertAgency;
  total_dives: number;
  created_at: string;
  updated_at: string;
}

export interface DiveSite {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  location: GeoPoint;
  country_code: string;
  region: string | null;
  depth_min: number;
  depth_max: number;
  difficulty: SiteDifficulty;
  site_type: SiteType;
  access_type: AccessType;
  created_by: string | null;
  verified: boolean;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export interface GeoPoint {
  lat: number;
  lng: number;
}

export interface Species {
  id: string;
  scientific_name: string;
  common_name: string | null;
  common_name_it: string | null;
  common_name_es: string | null;
  family: string | null;
  genus: string | null;
  order_name: string | null;
  class_name: string | null;
  phylum: string | null;
  kingdom: string | null;
  inat_taxon_id: number | null;
  worms_id: number | null;
  gbif_taxon_key: number | null;
  description: string | null;
  max_depth_m: number | null;
  min_depth_m: number | null;
  typical_length_cm: number | null;
  conservation_status: ConservationStatus | null;
  image_url: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export interface Sighting {
  id: string;
  user_id: string;
  dive_site_id: string;
  species_id: string;
  dive_log_id: string | null;
  observed_at: string;
  depth_m: number | null;
  water_temp_c: number | null;
  visibility_m: number | null;
  count: number;
  behavior_tags: string[];
  photo_urls: string[];
  confidence_level: ConfidenceLevel;
  verified_by: string | null;
  verified_at: string | null;
  notes: string | null;
  location: GeoPoint | null;
  source: SightingSource;
  external_id: string | null;
  created_at: string;
  updated_at: string;
}

export interface DiveLog {
  id: string;
  user_id: string;
  dive_site_id: string | null;
  operator_id: string | null;
  dive_date: string;
  dive_number: number | null;
  entry_time: string | null;
  exit_time: string | null;
  max_depth_m: number | null;
  avg_depth_m: number | null;
  duration_min: number | null;
  water_temp_surface_c: number | null;
  water_temp_bottom_c: number | null;
  visibility_m: number | null;
  current_strength: CurrentStrength | null;
  tank_start_bar: number | null;
  tank_end_bar: number | null;
  tank_size_l: number | null;
  gas_mix: GasMix | null;
  buddy_name: string | null;
  notes: string | null;
  rating: number | null;
  created_at: string;
  updated_at: string;
  synced_at: string | null;
}

export interface Operator {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  website: string | null;
  email: string | null;
  phone: string | null;
  address: string | null;
  location: GeoPoint | null;
  country_code: string | null;
  operator_type: OperatorType;
  padi_store_id: string | null;
  ssi_center_id: string | null;
  subscription_tier: SubscriptionTier;
  subscription_status: SubscriptionStatus;
  created_at: string;
  updated_at: string;
}

export interface OperatorUser {
  operator_id: string;
  user_id: string;
  role: OperatorRole;
}

export interface OperatorDiveSite {
  operator_id: string;
  dive_site_id: string;
  is_primary: boolean;
}

export interface SpeciesDiveSiteStats {
  species_id: string;
  dive_site_id: string;
  sighting_count: number;
  last_seen_at: string | null;
  avg_depth_m: number | null;
  best_season: string[];
  updated_at: string;
}

export interface UserLifeListEntry {
  user_id: string;
  species_id: string;
  first_seen_at: string;
  total_sightings: number;
  site_ids: string[];
  created_at: string;
}

export interface Badge {
  id: string;
  code: string;
  name: string;
  description: string;
  icon_url: string | null;
  criteria_type: BadgeCriteriaType;
  criteria_value: Record<string, unknown>;
  tier: number;
  created_at: string;
}

export interface UserBadge {
  user_id: string;
  badge_id: string;
  earned_at: string;
  context_json: Record<string, unknown>;
}

export interface PaginatedResponse<T> {
  data: T[];
  page: number;
  limit: number;
  total: number;
}

export interface UpdateUserDto {
  username?: string;
  full_name?: string;
  avatar_url?: string;
  bio?: string;
  certification_level?: CertLevel;
  certification_agency?: CertAgency;
  total_dives?: number;
}

export interface IdentifySpeciesDto {
  image_url: string;
}

export interface SpeciesIdentificationResult {
  taxon_id: number;
  scientific_name: string;
  common_name: string | null;
  confidence: number;
  image_url: string | null;
}

export interface MediaUploadRequestDto {
  filename: string;
  content_type: string;
}

export interface MediaUploadResponseDto {
  upload_url: string;
  key: string;
}

export interface MediaConfirmDto {
  key: string;
}

export interface MediaConfirmResponseDto {
  url: string;
  key: string;
}

export interface UpdateOperatorDto {
  name?: string;
  description?: string;
  website?: string;
  email?: string;
  phone?: string;
  address?: string;
}

export interface DiveSiteSummary {
  id: string;
  name: string;
  slug: string;
  country_code: string;
  region: string | null;
  distance_m?: number;
}

export interface SpeciesAtSite {
  species_id: string;
  scientific_name: string;
  common_name: string | null;
  common_name_it: string | null;
  common_name_es: string | null;
  image_url: string | null;
  conservation_status: ConservationStatus | null;
  sighting_count: number;
  last_seen_at: string | null;
  avg_depth_m: number | null;
}

export interface SiteWithSpecies {
  dive_site_id: string;
  name: string;
  slug: string;
  country_code: string;
  region: string | null;
  sighting_count: number;
  last_seen_at: string | null;
}

export interface UserProfile extends User {
  life_list_count?: number;
  badge_count?: number;
}

export interface UserDiveStats {
  total_dives: number;
  total_species: number;
  total_sites: number;
  total_countries: number;
  deepest_dive_m: number | null;
  longest_dive_min: number | null;
  total_bottom_time_min: number;
}

export interface OperatorAnalytics {
  total_customers: number;
  dives_in_window: number;
  active_sites: number;
  top_species: Array<{
    species_id: string;
    common_name: string | null;
    scientific_name: string;
    sighting_count: number;
  }>;
}

export interface OperatorCustomer {
  user_id: string;
  username: string;
  full_name: string | null;
  certification_level: CertLevel;
  total_dives_with_operator: number;
  first_dive: string;
  last_dive: string;
}

export interface SearchResult {
  type: 'site' | 'species';
  id: string;
  title: string;
  subtitle: string | null;
  slug?: string;
  rank: number;
}

export interface UnifiedSearchResponse {
  query: string;
  results: SearchResult[];
}
