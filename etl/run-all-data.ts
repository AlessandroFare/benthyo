import 'dotenv/config';
import { logger } from './shared/logger';
import { runApifyGoogleMapsEtl } from './apify-google-maps/index';
import { runDiveNumberEtl } from './divenumber/index';
import { runGbifEtl } from './gbif/index';
import { runInatObservationsEtl } from './inat-observations/index';
import { runInatTaxonLookupEtl } from './inat-taxon-lookup/index';
import { runInaturalistImageEtl } from './inaturalist-images/index';
import { runObisEtl } from './obis/index';
import { runSeamapEtl } from './seamap/index';
import { runRlsEtl } from './rls/index';
import { runOpenDiveMapEtl } from './opendivemap/index';
import { runOverpassEtl } from './overpass/index';
import { runWikidataEtl } from './wikidata/index';
import { runDiveSiteDiscoveryEtl } from './dive-site-discovery/index';
import { runDiveMapVisionEtl } from './dive-map-vision/index';
import { runWikivoyageEtl } from './wikivoyage/index';
import { runSpeciesSeedEtl } from './species-seed/index';
import { runTavilySpeciesEtl } from './tavily-species/index';
import { runWikimediaImagesEtl } from './wikimedia-images/index';
import { runWormsEtl } from './worms/index';
import { runFishbaseEtl } from './fishbase/index';
import { isMainModule } from './shared/cli';
import { createClient } from '@supabase/supabase-js';

/**
 * Run the full Benthyo data ETL pipeline in dependency order.
 *
 * This file is the SINGLE SOURCE OF TRUTH for ETL ordering. README.md
 * and docs/decisions.md (ADR-015) are kept in sync with it.
 *
 * Order is significant:
 *   1. Iconic species seed (real IDs + it/es names + photos from live APIs).
 *   2. Dive sites in parallel (opendivemap, overpass, divenumber), so
 *      occurrences can be matched to nearby sites.
 *   3. LLM dive-site discovery (OpenCode Zen enumeration + Nominatim), after
 *      the map sources so it can dedup against them.
 *   4. Apify Google Maps last in the site batch (slowest source).
 *   5. GBIF + OBIS + SEAMAP + iNat occurrences IN PARALLEL (independent sources).
 *   6. Open-water reconciliation: placeholder sites for unmatched sightings.
 *   7. WoRMS enrichment AFTER occurrences, so it enriches freshly-imported
 *      species with taxonomy + it/es/en common names (it used to run first,
 *      which was a no-op on a fresh DB).
 *   8. inat-taxon-lookup BEFORE the image backfills (images need inat_taxon_id).
 *   9. Image backfills in increasing cost / decreasing quality:
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

  // 1. Iconic species seed. Guarantees whale shark, manta, mola mola, sea
  //    turtles, clownfish etc. always exist with REAL taxon IDs + it/es names
  //    + a photo, resolved live from iNaturalist + WoRMS. Runs first so these
  //    species are present and correctly linked before anything references
  //    them, and independent of what the occurrence sources return.
  await step('species-seed', runSpeciesSeedEtl);

  // 2. Dive site sources in parallel, each isolated so one source's
  //    failure does not discard the others' ingested sites.
  await parallelSources([
    { name: 'opendivemap', fn: runOpenDiveMapEtl },
    { name: 'overpass', fn: runOverpassEtl },
    { name: 'divenumber', fn: runDiveNumberEtl },
    // Wikidata SPARQL: hand-curated, exact coordinates for shipwrecks, reefs,
    // cenotes, blue holes, and seamounts. Runs alongside the other map sources.
    { name: 'wikidata', fn: runWikidataEtl },
    // Wikivoyage: human-curated dive guides (CC BY-SA) with exact coordinates,
    // depth, and conditions. Runs alongside other site sources for dedup.
    { name: 'wikivoyage', fn: runWikivoyageEtl },
  ]);

  // 3. LLM-driven discovery. Runs AFTER the map-based sources so they can
  //    dedup against everything already ingested.
  //    3a. OpenCode Zen enumeration + Nominatim geocoding.
  //    3b. Dive-map vision: image search + Llama 4 Scout OCR for dive maps.
  //    Both no-op gracefully if their API keys are unset.
  await step('dive-site-discovery', runDiveSiteDiscoveryEtl);
  await step('dive-map-vision', runDiveMapVisionEtl);

  // 4. Apify Google Maps crawl. Last in the site batch because it is the slowest.
  await step('apify:google-maps', runApifyGoogleMapsEtl);

  // 5. GBIF + OBIS + SEAMAP + iNaturalist research-grade observations in
  // parallel. All are independent occurrence sources that link to species
  // via scientific name and to dive sites via nearby_dive_sites.
  //
  // iNaturalist (quality_grade=research) is included here because it is
  // community-verified, GPS-accurate, and complements GBIF/OBIS with
  // richer photo data and finer species-level IDs for Mediterranean marine
  // megafauna. Source tag = 'inat' keeps dedup distinct from gbif/obis.
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
    { name: 'inat:observations', fn: runInatObservationsEtl },
  ];
  if (process.env.RLS_API_URL) {
    occurrenceSources.push({ name: 'rls', fn: runRlsEtl });
  } else {
    logger.info('Skipping RLS source — RLS_API_URL not set (no public RLS API; see report)');
  }
  await parallelSources(occurrenceSources);

  // 6. Post-import reconciliation: create placeholder sites for any
  // sightings that didn't link to a known site within 30 km.
  await step('reconcile-unmatched-occurrences', runOpenWaterReconciliation);

  // 7. WoRMS taxonomy enrichment. Moved AFTER the occurrence imports (it used
  // to run first, which did nothing on a fresh DB) so it enriches the freshly
  // imported species with worms_id, canonical taxonomy, and — crucially —
  // Italian/Spanish/English common names for search. Cursor-paginated and
  // capped via WORMS_MAX so a single run stays bounded.
  await step('worms', runWormsEtl);

  // 7b. FishBase/SeaLifeBase enrichment. Runs after WoRMS (which sets canonical
  // taxonomy + vernaculars) and adds real depth ranges, habitat descriptors,
  // max length, and any missing EN/IT/ES common names from the FishBase and
  // SeaLifeBase static Parquet snapshots. Fill-when-empty, so it never clobbers
  // curated seed or WoRMS names.
  await step('fishbase', runFishbaseEtl);

  // 8. Resolve iNaturalist taxon IDs for species missing one. MUST run
  // before the image backfills, because inaturalist-images uses inat_taxon_id.
  await step('inat:taxon-lookup', runInatTaxonLookupEtl);

  // 9. Image backfills, in increasing cost / decreasing quality.
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
  for (const source of ['gbif', 'obis', 'seamap', 'inat', 'rls'] as const) {
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
