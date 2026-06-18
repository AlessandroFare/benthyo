/** Shared helpers for normalizing dive site rows across ETL sources. */

export interface DiveSiteRow {
  name: string;
  slug: string;
  description: string | null;
  location: string;
  country_code: string;
  region: string | null;
  depth_min: number;
  depth_max: number;
  difficulty: string;
  site_type: string;
  access_type: string;
  verified: boolean;
  metadata: Record<string, unknown>;
}

export function slugify(name: string): string {
  return name
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')   // rimuovi diacritici
    .replace(/[^\x00-\x7F]/g, '-')     // tutti i non-ASCII → -
    .replace(/[^a-z0-9-]/g, '-')       // qualsiasi altro carattere non valido → -
    .replace(/-{2,}/g, '-')            // collassa -- multipli in uno solo
    .replace(/^-|-$/g, '')             // rimuovi - iniziali/finali
    .slice(0, 80)
    || 'site';                          // fallback se il risultato è vuoto
}

export function uniqueSlug(base: string, suffix: string, seen: Set<string>): string {
  let slug = base;
  if (seen.has(slug)) {
    slug = `${base}-${suffix}`.slice(0, 80);
  }
  seen.add(slug);
  return slug;
}

export function geographyPoint(lon: number, lat: number): string {
  return `SRID=4326;POINT(${lon} ${lat})`;
}

const SITE_TYPES = new Set(['reef', 'wall', 'wreck', 'cave', 'pinnacle', 'muck', 'other']);
const DIFFICULTIES = new Set(['beginner', 'intermediate', 'advanced', 'technical']);
const ACCESS_TYPES = new Set(['shore', 'boat', 'liveaboard']);

export function normalizeSiteType(value: string | undefined): string {
  const lower = (value ?? 'other').toLowerCase();
  if (SITE_TYPES.has(lower)) return lower;
  if (lower.includes('wreck')) return 'wreck';
  if (lower.includes('wall')) return 'wall';
  if (lower.includes('cave') || lower.includes('cavern')) return 'cave';
  if (lower.includes('pinnacle')) return 'pinnacle';
  if (lower.includes('muck')) return 'muck';
  if (lower.includes('reef') || lower.includes('kelp')) return 'reef';
  return 'other';
}

export function inferDifficultyFromText(text: string): string {
  const hint = text.toLowerCase();
  if (hint.includes('technical') || hint.includes('trimix')) return 'technical';
  if (hint.includes('advanced')) return 'advanced';
  if (hint.includes('beginner') || hint.includes('easy') || hint.includes('novice')) {
    return 'beginner';
  }
  return 'intermediate';
}

export function normalizeDifficulty(value: string | undefined, fallbackText = ''): string {
  const lower = (value ?? '').toLowerCase();
  if (DIFFICULTIES.has(lower)) return lower;
  return inferDifficultyFromText(fallbackText);
}

export function normalizeAccessType(value: string | undefined, fallbackText = ''): string {
  const lower = (value ?? '').toLowerCase();
  if (ACCESS_TYPES.has(lower)) return lower;
  const hint = fallbackText.toLowerCase();
  if (hint.includes('liveaboard')) return 'liveaboard';
  if (hint.includes('boat')) return 'boat';
  if (lower === 'other') return 'shore';
  return 'shore';
}

export function normalizeCountryCode(value: string | undefined): string {
  if (value && value.length === 2) return value.toUpperCase();
  return 'XX';
}

export interface OverpassRegion {
  name: string;
  south: number;
  west: number;
  north: number;
  east: number;
}

/** Regional bounding boxes for global Overpass dive-site queries. */
export const OVERPASS_REGIONS: OverpassRegion[] = [
  { name: 'mediterranean', south: 30, west: -6, north: 46, east: 36 },
  { name: 'nordic', south: 55, west: -25, north: 72, east: 35 },
  { name: 'north_atlantic', south: 25, west: -85, north: 55, east: -10 },
  { name: 'caribbean', south: 10, west: -90, north: 28, east: -60 },
  { name: 'red_sea', south: 12, west: 32, north: 30, east: 44 },
  { name: 'indian_ocean', south: -10, west: 40, north: 25, east: 100 },
  { name: 'southeast_asia', south: -10, west: 90, north: 20, east: 140 },
  { name: 'pacific', south: -30, west: 140, north: 30, east: -120 },
  { name: 'australia_nz', south: -45, west: 110, north: -10, east: 180 },
];

export function buildOverpassQuery(region: OverpassRegion): string {
  const { south, west, north, east } = region;
  return `
[out:json][timeout:180];
(
  node["sport"="scuba_diving"](${south},${west},${north},${east});
  node["leisure"="diving"](${south},${west},${north},${east});
  node["tourism"="attraction"]["scuba_diving"](${south},${west},${north},${east});
  way["sport"="scuba_diving"](${south},${west},${north},${east});
);
out center tags;
`;
}
