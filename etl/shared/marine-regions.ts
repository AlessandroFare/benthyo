/**
 * Global marine regions for species & dive site ETL queries.
 *
 * Replaces the hardcoded Mediterranean-only scope in GBIF, OBIS, iNat, SEAMAP.
 * Each region is a WKT polygon usable directly in GBIF/OBIS geometry params,
 * and also carries a lat/lng bbox for iNaturalist.
 *
 * Coverage: every major recreational diving region on Earth.
 * Order roughly follows dive-site popularity: tropical first, then temperate.
 */

export interface MarineRegion {
  /** Human-readable name (used in logs). */
  name: string;
  /** WKT POLYGON for GBIF/OBIS/SEAMAP geometry queries. */
  wkt: string;
  /** Bounding box for iNaturalist API (swlat,swlng,nelat,nelng). */
  bbox: { swlat: number; swlng: number; nelat: number; nelng: number };
}

export const GLOBAL_MARINE_REGIONS: MarineRegion[] = [
  {
    name: 'caribbean',
    wkt: 'POLYGON((-90 10, -60 10, -60 28, -90 28, -90 10))',
    bbox: { swlat: 10, swlng: -90, nelat: 28, nelng: -60 },
  },
  {
    name: 'red_sea',
    wkt: 'POLYGON((32 12, 44 12, 44 30, 32 30, 32 12))',
    bbox: { swlat: 12, swlng: 32, nelat: 30, nelng: 44 },
  },
  {
    name: 'indian_ocean',
    wkt: 'POLYGON((40 -10, 100 -10, 100 25, 40 25, 40 -10))',
    bbox: { swlat: -10, swlng: 40, nelat: 25, nelng: 100 },
  },
  {
    name: 'southeast_asia',
    wkt: 'POLYGON((90 -10, 140 -10, 140 20, 90 20, 90 -10))',
    bbox: { swlat: -10, swlng: 90, nelat: 20, nelng: 140 },
  },
  {
    name: 'australia_nz',
    wkt: 'POLYGON((110 -45, 180 -45, 180 -10, 110 -10, 110 -45))',
    bbox: { swlat: -45, swlng: 110, nelat: -10, nelng: 180 },
  },
  {
    name: 'pacific',
    wkt: 'POLYGON((-180 -30, -120 -30, -120 30, -180 30, -180 -30))',
    bbox: { swlat: -30, swlng: -180, nelat: 30, nelng: -120 },
  },
  {
    name: 'mediterranean',
    wkt: 'POLYGON((-6 30, 36 30, 36 46, -6 46, -6 30))',
    bbox: { swlat: 30, swlng: -6, nelat: 46, nelng: 36 },
  },
  {
    name: 'north_atlantic',
    wkt: 'POLYGON((-85 25, -10 25, -10 55, -85 55, -85 25))',
    bbox: { swlat: 25, swlng: -85, nelat: 55, nelng: -10 },
  },
  {
    name: 'nordic',
    wkt: 'POLYGON((-25 55, 35 55, 35 72, -25 72, -25 55))',
    bbox: { swlat: 55, swlng: -25, nelat: 72, nelng: 35 },
  },
  {
    name: 'east_africa',
    wkt: 'POLYGON((32 -30, 60 -30, 60 10, 32 10, 32 -30))',
    bbox: { swlat: -30, swlng: 32, nelat: 10, nelng: 60 },
  },
  {
    name: 'japan_korea',
    wkt: 'POLYGON((125 25, 150 25, 150 45, 125 45, 125 25))',
    bbox: { swlat: 25, swlng: 125, nelat: 45, nelng: 150 },
  },
];

/**
 * Return regions matching the comma-separated REGIONS env var, or all regions.
 * Example: GBIF_REGIONS=caribbean,red_sea → runs only those two.
 */
export function resolveRegions(envKey: string): MarineRegion[] {
  const raw = process.env[envKey];
  if (!raw) return GLOBAL_MARINE_REGIONS;
  const names = new Set(raw.split(',').map((s) => s.trim().toLowerCase()));
  const filtered = GLOBAL_MARINE_REGIONS.filter((r) => names.has(r.name));
  if (filtered.length === 0) {
    throw new Error(
      `${envKey}=${raw} matched no known regions. Known: ${GLOBAL_MARINE_REGIONS.map((r) => r.name).join(', ')}`,
    );
  }
  return filtered;
}
