import type { SupabaseClient } from '@supabase/supabase-js';
import { logger } from './logger';

/**
 * Normalisation helpers shared by the occurrence-based ETL sources
 * (obis, seamap, rls, gbif).
 *
 * These exist because external biodiversity APIs return values that do not
 * map cleanly onto the `sightings` table:
 *   - OBIS v3 returns `date_start` / `date_mid` as epoch MILLISECONDS, not
 *     ISO strings. Inserting the raw value into a `timestamptz` column throws
 *     "date/time field value out of range" / "time zone displacement out of
 *     range".
 *   - `individualCount` / `abundance` can be fractional (densities), but
 *     `sightings.count` is an `integer` with a `count > 0` check.
 *   - depth fields can be negative or absent, but `sightings.depth_m` has a
 *     `depth_m >= 0` check.
 */

function isValidDate(d: Date): boolean {
  return !Number.isNaN(d.getTime());
}

/**
 * Convert an external observation date into an ISO-8601 string, or null when
 * it cannot be parsed into a plausible value. Accepts epoch-millisecond
 * numbers / numeric strings (OBIS) and ISO date strings.
 */
export function normalizeObservedAt(raw: unknown): string | null {
  if (raw == null) return null;

  let date: Date | null = null;
  if (typeof raw === 'number') {
    date = new Date(raw);
  } else if (typeof raw === 'string') {
    const trimmed = raw.trim();
    if (trimmed === '') return null;
    // Epoch milliseconds (optionally negative) serialised as a string.
    if (/^-?\d{11,}$/.test(trimmed)) {
      date = new Date(Number(trimmed));
    } else {
      date = new Date(trimmed);
    }
  } else {
    return null;
  }

  if (!isValidDate(date)) return null;
  const year = date.getUTCFullYear();
  // Reject implausible years (data glitches that Postgres would reject anyway).
  if (year < 1700 || year > 2100) return null;
  return date.toISOString();
}

/** Coerce an external count/abundance into a positive integer (default 1). */
export function normalizeCount(raw: unknown): number {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return 1;
  return Math.max(1, Math.round(n));
}

/** Coerce an external depth into a non-negative number, or null. */
export function normalizeDepth(raw: unknown): number | null {
  if (raw == null || raw === '') return null;
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 0) return null;
  return n;
}

/**
 * Fail fast if the configured ETL system user does not exist. Occurrence
 * imports write `sightings.user_id = ETL_SYSTEM_USER_ID`; when that id is
 * missing every single row fails the `sightings_user_id_fkey` constraint,
 * producing thousands of identical errors. A single up-front check turns that
 * into one actionable message.
 */
export async function assertSystemUserExists(
  supabase: SupabaseClient,
  systemUserId: string,
): Promise<void> {
  const { data, error } = await supabase
    .from('users')
    .select('id')
    .eq('id', systemUserId)
    .maybeSingle();
  if (error) {
    throw new Error(`Failed to verify ETL_SYSTEM_USER_ID: ${error.message}`);
  }
  if (!data) {
    throw new Error(
      'ETL_SYSTEM_USER_ID does not exist in public.users — ' +
        'seed a system user (see scripts/seed-etl-system-user.sql) before running occurrence imports',
    );
  }
}

/**
 * Link every unmatched sighting of a given source to its nearest dive site
 * within `radiusKm`, in a SINGLE set-based SQL query.
 *
 * This replaces the old per-occurrence `nearby_dive_sites` RPC calls (one
 * network round-trip per row). The occurrence ETLs now insert sightings with
 * only their `location` and a NULL `dive_site_id`, then call this helper once
 * at the end. See migration 063_batch_match_sightings.sql.
 *
 * Non-fatal: a failure is logged and swallowed so the import is not lost —
 * run-all-data's reconciliation step will still pick up unmatched rows.
 */
export async function matchSightingsToSites(
  supabase: SupabaseClient,
  source: string,
  radiusKm: number,
): Promise<number> {
  const { data, error } = await supabase.rpc('match_sightings_to_nearby_sites', {
    p_source: source,
    p_radius_km: radiusKm,
  });
  if (error) {
    logger.warn(`match_sightings_to_nearby_sites(${source}) failed: ${error.message}`);
    return 0;
  }
  const matched = typeof data === 'number' ? data : Number(data ?? 0);
  logger.info(`Batch-matched ${matched} ${source} sightings to nearby dive sites`);
  return matched;
}
