export type Uuid = string;

export type Difficulty = "OW" | "AOW" | "Deep" | "Tech" | "Cave" | "Wreck";
export type Current = "None" | "Mild" | "Moderate" | "Strong" | "Variable";
export type EntryType = "Beach" | "Boat" | "Shore" | "Pier" | "Liveaboard";
export type VerificationStatus =
  | "pending"
  | "photo_required"
  | "community_verified"
  | "expert_verified"
  | "research_grade";

export interface Coordinates {
  lat: number;
  lon: number;
}

export interface DiveSite {
  id: Uuid;
  name: string;
  slug: string;
  coordinates: Coordinates;
  region: string;
  country_code: string;
  depth_min: number | null;
  depth_max: number | null;
  difficulty: Difficulty;
  visibility_avg: number | null;
  visibility_min: number | null;
  visibility_max: number | null;
  water_temp_min: number | null;
  water_temp_max: number | null;
  current: Current;
  best_months: number[];
  entry_type: EntryType;
  certifications_required: string[];
  hazards: string[];
  description_short: string;
  description_long: string;
  photo_count: number;
  review_count: number;
  avg_rating: number | null;
  created_at: string;
  updated_at: string;
}

export interface Species {
  id: Uuid;
  scientific_name: string;
  common_name: string | null;
  kingdom: string | null;
  phylum: string | null;
  class: string | null;
  order: string | null;
  family: string | null;
  genus: string | null;
  conservation_status: string | null;
  description: string | null;
  photo_url: string | null;
  is_marine: boolean;
  created_at: string;
  updated_at: string;
}

export interface Sighting {
  id: Uuid;
  user_id: Uuid;
  dive_site_id: Uuid | null;
  species_id: Uuid;
  observed_at: string;
  depth_m: number | null;
  count: number | null;
  behavior: string | null;
  photo_ids: Uuid[];
  notes: string | null;
  verification_status: VerificationStatus;
  gbif_occurrence_id: Uuid | null;
  license: "CC0" | "CC-BY" | "CC-BY-NC";
  created_at: string;
  updated_at: string;
}

export interface SightingWithDetails extends Sighting {
  dive_site: Pick<DiveSite, "id" | "name" | "region"> | null;
  species: Pick<Species, "id" | "scientific_name" | "common_name"> | null;
}

export interface Operator {
  id: Uuid;
  name: string;
  slug: string;
  email: string;
  subscription_tier: "free" | "starter" | "pro" | "enterprise";
  subscription_status: "active" | "trialing" | "past_due" | "cancelled";
  region: string;
  country_code: string;
  website: string | null;
  logo_url: string | null;
  onboarded_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface Customer {
  id: Uuid;
  operator_id: Uuid;
  email: string;
  first_name: string;
  last_name: string;
  certification_level: string | null;
  total_dives: number;
  last_dive_at: string | null;
  tags: string[];
  created_at: string;
  updated_at: string;
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
  verifications_distribution: { name: VerificationStatus; value: number }[];
}

export interface Paginated<T> {
  data: T[];
  total: number;
  page: number;
  page_size: number;
}

export type ApiError = {
  message: string;
  statusCode: number;
  code?: string;
};

export interface ActivityItem {
  id: Uuid;
  type: "sighting" | "dive" | "customer" | "site";
  title: string;
  description: string;
  occurred_at: string;
  metadata?: Record<string, string | number>;
}

export interface DashboardCharts {
  sightings_trend: TimeSeriesPoint[];
  dives_by_site: TimeSeriesPoint[];
}

export interface OperatorSite {
  id: Uuid;
  dive_site_id: Uuid;
  name: string;
  region: string;
  country_code: string;
  depth_max: number | null;
  difficulty: Difficulty;
  is_primary: boolean;
  sighting_count: number;
  added_at: string;
}

export interface CustomerDetail extends Customer {
  recent_dives: {
    id: Uuid;
    dive_site_name: string;
    dive_date: string;
    max_depth_m: number;
    duration_min: number;
  }[];
  species_seen: {
    id: Uuid;
    name: string;
    sighting_count: number;
    last_seen_at: string;
  }[];
}

export interface HeatmapCell {
  day: number;
  hour: number;
  value: number;
}

export interface DiversityPoint {
  family: string;
  count: number;
  percentage: number;
}

export interface DepthBucket {
  range: string;
  count: number;
}

export interface RetentionCohort {
  cohort: string;
  month_0: number;
  month_1: number;
  month_2: number;
  month_3: number;
}

export interface AnalyticsData {
  heatmap: HeatmapCell[];
  diversity: DiversityPoint[];
  depth_histogram: DepthBucket[];
  retention: RetentionCohort[];
}

export interface SpeciesRanked {
  id: Uuid;
  scientific_name: string;
  common_name: string | null;
  family: string | null;
  sighting_count: number;
  site_count: number;
  last_seen_at: string | null;
  conservation_status: string | null;
  photo_url: string | null;
}

export interface SpeciesDetail extends Species {
  sighting_count: number;
  site_count: number;
  avg_depth_m: number | null;
  top_sites: { id: Uuid; name: string; count: number }[];
  monthly_trend: TimeSeriesPoint[];
}

export interface TeamMember {
  id: Uuid;
  user_id: Uuid;
  email: string;
  full_name: string | null;
  role: "owner" | "admin" | "staff";
  invited_at: string;
  accepted_at: string | null;
}

export interface SubscriptionInfo {
  tier: Operator["subscription_tier"];
  status: Operator["subscription_status"];
  current_period_end: string | null;
  sites_limit: number;
  team_limit: number;
  features: string[];
}

export interface SettingsData {
  operator: Operator;
  team: TeamMember[];
  subscription: SubscriptionInfo;
}
