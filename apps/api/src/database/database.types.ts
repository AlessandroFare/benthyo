/*
 * TypeScript shapes mirroring the Supabase migrations. These keep the
 * API layer strongly-typed without requiring a generated supabase-js
 * client (which would come from `supabase gen types`).
 */

export type CertLevel = 'OW' | 'AOW' | 'Rescue' | 'Divemaster' | 'Instructor';
export type CertAgency = 'PADI' | 'SSI' | 'RAID' | 'CMAS' | 'SDI' | 'other';
export type SiteDifficulty = 'beginner' | 'intermediate' | 'advanced' | 'technical';
export type SiteType = 'reef' | 'wall' | 'wreck' | 'cave' | 'pinnacle' | 'muck' | 'other';
export type AccessType = 'shore' | 'boat' | 'liveaboard';
export type ConservationStatus = 'LC' | 'NT' | 'VU' | 'EN' | 'CR' | 'DD' | 'NE';
export type ConfidenceLevel = 'uncertain' | 'likely' | 'certain';
export type CurrentStrength = 'none' | 'light' | 'moderate' | 'strong';
export type GasMix = 'air' | 'nitrox32' | 'nitrox36' | 'trimix';
export type OperatorType = 'dive_center' | 'liveaboard' | 'resort';
export type OperatorRole = 'owner' | 'admin' | 'staff';
export type SubscriptionTier = 'free' | 'starter' | 'pro';
export type SubscriptionStatus = 'active' | 'past_due' | 'canceled' | 'trialing';
export type BadgeCriteriaType = 'dive_count' | 'species_count' | 'site_count' | 'region' | 'manual';
export type SightingSource = 'user' | 'gbif' | 'obis' | 'inaturalist' | 'manual';

export interface UserProfile {
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
  // GEOGRAPHY(Point) is exposed as a WKT string such as "POINT(lng lat)".
  location: string;
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

export interface Operator {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  website: string | null;
  email: string | null;
  phone: string | null;
  address: string | null;
  location: string | null;
  country_code: string | null;
  operator_type: OperatorType;
  padi_store_id: string | null;
  ssi_center_id: string | null;
  subscription_tier: SubscriptionTier;
  subscription_status: SubscriptionStatus;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export interface OperatorUser {
  operator_id: string;
  user_id: string;
  role: OperatorRole;
  invited_at: string;
  accepted_at: string | null;
}

export interface OperatorDiveSite {
  operator_id: string;
  dive_site_id: string;
  is_primary: boolean;
  added_at: string;
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
  max_depth_m: number;
  avg_depth_m: number | null;
  duration_min: number;
  water_temp_surface_c: number | null;
  water_temp_bottom_c: number | null;
  visibility_m: number | null;
  current_strength: CurrentStrength | null;
  tank_start_bar: number | null;
  tank_end_bar: number | null;
  tank_size_l: number | null;
  gas_mix: GasMix;
  buddy_name: string | null;
  notes: string | null;
  rating: number | null;
  synced_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface Sighting {
  id: string;
  user_id: string;
  dive_site_id: string | null;
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
  location: string | null;
  source: SightingSource;
  external_id: string | null;
  created_at: string;
  updated_at: string;
}

export interface SpeciesDiveSiteStats {
  species_id: string;
  dive_site_id: string;
  sighting_count: number;
  last_seen_at: string | null;
  avg_depth_m: number | null;
  best_season: number[];
  updated_at: string;
}

export interface UserLifeList {
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
