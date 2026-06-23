import 'dotenv/config';
import { logger } from './shared/logger';
import { runApifyGoogleMapsEtl } from './apify-google-maps/index';
import { runDiveNumberEtl } from './divenumber/index';
import { runGbifEtl } from './gbif/index';
import { runInatTaxonLookupEtl } from './inat-taxon-lookup/index';
import { runInaturalistImageEtl } from './inaturalist-images/index';
import { runObisEtl } from './obis/index';
import { runSeamapEtl } from './seamap/index';
import { runRlsEtl } from './rls/index';
import { runOpenDiveMapEtl } from './opendivemap/index';
import { runOverpassEtl } from './overpass/index';
import { runTavilySpeciesEtl } from './tavily-species/index';
import { runWikimediaImagesEtl } from './wikimedia-images/index';
import { runWormsEtl } from './worms/index';
import { isMainModule } from './shared/cli';
import { createClient } from '@supabase/supabase-js';

/**
 * Run the full Benthyo data ETL pipeline in dependency order.
 *
 * This file is the SINGLE SOURCE OF TRUTH for ETL ordering. README.md
 * and docs/decisions.md (ADR-015) are kept in sync with it.
 *
 * Order is significant:
 *   1. WoRMS taxonomy first, so GBIF/OBIS occurrences can link to species
 *      by canonical scientific name.
 *   2. Dive sites in parallel (opendivemap, overpass, divenumber), so
 *      occurrences can be matched to nearby sites.
 *   3. Apify Google Maps last in the site batch (slowest source).
 *   4. GBIF + OBIS occurrences IN PARALLEL (independent sources).
 *   5. Open-water reconciliation: placeholder sites for unmatched sightings.
 *   6. inat-taxon-lookup BEFORE the image backfills (images need inat_taxon_id).
 *   7. Image backfills in increasing cost / decreasing quality:
 *      wikimedia -> inaturalist -> tavily.
 *
 * Each top-level step is isolated: a failure is logged and the pipeline
 * continues to the next step, so one flaky upstream (e.g. a Tavily 429 or
 * a GBIF timeout) does not abort the entire nightly run. The process exits
 * non-zero if any step failed.
 */
export async function runAllDataEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting full Benthyo data ETL pipeline');

  const failures: string[] = [];

  /** Run a step, isolating and recording any failure. */
  async function step(name: string, fn: () => Promise<unknown>): Promise<void> {
    const stepStart = Date.now();
    try {
      await fn();
      logger.info(`Step "${name}" finished in ${Date.now() - stepStart}ms`);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      failures.push(`${name}: ${message}`);
      logger.error(`Step "${name}" failed (continuing)`, { error: message });
    }
  }

  /**
   * Run several independent sources concurrently with per-source failure
   * isolation. Unlike Promise.all, one source failing does not abort its
   * siblings — each is recorded individually so the others' work is kept,
   * matching the README's "a single failing source is logged and the
   * pipeline continues" guarantee inside a parallel batch.
   */
  async function parallelSources(
    sources: Array<{ name: string; fn: () => Promise<unknown> }>,
  ): Promise<void> {
    const results = await Promise.allSettled(sources.map((s) => s.fn()));
    results.forEach((r, i) => {
      if (r.status === 'rejected') {
        const message =
          r.reason instanceof Error ? r.reason.message : String(r.reason);
        failures.push(`${sources[i].name}: ${message}`);
        logger.error(`Source "${sources[i].name}" failed (continuing)`, {
          error: message,
        });
      }
    });
  }

  // 1. Taxonomy first.
  await step('worms', runWormsEtl);

  // 2. Dive site sources in parallel, each isolated so one source's
  //    failure does not discard the others' ingested sites.
  await parallelSources([
    { name: 'opendivemap', fn: runOpenDiveMapEtl },
    { name: 'overpass', fn: runOverpassEtl },
    { name: 'divenumber', fn: runDiveNumberEtl },
  ]);

  // 3. Apify Google Maps crawl. Last in the site batch because it is the slowest.
  await step('apify:google-maps', runApifyGoogleMapsEtl);

  // 4. GBIF + OBIS + SEAMAP occurrences in parallel. They link to
  // species via scientific name and to dive sites via nearby_dive_sites;
  // none depends on another, so we run them concurrently.
  //
  // RLS (Reef Life Survey) is intentionally EXCLUDED by default: RLS has no
  // public/free JSON API (its data is distributed as CSV/Zenodo dumps and via
  // the AODN WFS, not a REST endpoint). The previous `api.reeflifesurvey.com`
  // endpoint does not resolve. The source only runs if RLS_API_URL is set to a
  // real endpoint you have verified. See PRODUCTION_PASS_REPORT.md.
  const occurrenceSources = [
    { name: 'gbif', fn: runGbifEtl },
    { name: 'obis', fn: runObisEtl },
    { name: 'seamap', fn: runSeamapEtl },
  ];
  if (process.env.RLS_API_URL) {
    occurrenceSources.push({ name: 'rls', fn: runRlsEtl });
  } else {
    logger.info('Skipping RLS source — RLS_API_URL not set (no public RLS API; see report)');
  }
  await parallelSources(occurrenceSources);

  // 5. Post-import reconciliation: create placeholder sites for any
  // sightings that didn't link to a known site within 30 km.
  await step('reconcile-unmatched-occurrences', runOpenWaterReconciliation);

  // 6. Resolve iNaturalist taxon IDs for species missing one. MUST run
  // before the image backfills, because inaturalist-images uses inat_taxon_id.
  await step('inat:taxon-lookup', runInatTaxonLookupEtl);

  // 7. Image backfills, in increasing cost / decreasing quality.
  await step('wikimedia:images', runWikimediaImagesEtl);
  await step('inaturalist:images', runInaturalistImageEtl);
  await step('tavily:species', runTavilySpeciesEtl);

  const elapsed = Date.now() - startedAt;
  if (failures.length > 0) {
    logger.error(`Full data ETL finished in ${elapsed}ms with ${failures.length} failed step(s)`, {
      failures,
    });
    throw new Error(`ETL pipeline completed with ${failures.length} failed step(s)`);
  }
  logger.info(`Full data ETL finished in ${elapsed}ms (all steps OK)`);
}

/**
 * Call the reconcile_unmatched_occurrences() SQL function for GBIF
 * then OBIS. Service-role client required (the function is
 * SECURITY DEFINER but the underlying UPDATE is gated by the
 * diver_site policies).
 */
async function runOpenWaterReconciliation(): Promise<void> {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    logger.warn('Skipping open-water reconciliation: SUPABASE creds missing');
    return;
  }
  const supabase = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  for (const source of ['gbif', 'obis', 'seamap', 'rls'] as const) {
    const { data, error } = await supabase.rpc('reconcile_unmatched_occurrences', {
      p_source: source,
      p_radius_meters: 30000,
    });
    if (error) {
      logger.error(`reconcile_unmatched_occurrences(${source}) failed: ${error.message}`);
      continue;
    }
    if (Array.isArray(data) && data.length > 0) {
      const row = data[0] as { created_sites: number; linked_sightings: number };
      logger.info(
        `Reconciled ${source}: created_sites=${row.created_sites}, linked_sightings=${row.linked_sightings}`,
      );
    }
  }
}

if (isMainModule(import.meta.url)) {
  runAllDataEtl().catch((err) => {
    logger.error('Full data ETL failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  });
}
