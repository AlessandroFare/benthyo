import 'dotenv/config';
import { logger } from './shared/logger';
import { runApifyGoogleMapsEtl } from './apify-google-maps/index';
import { runDiveNumberEtl } from './divenumber/index';
import { runGbifEtl } from './gbif/index';
import { runInatTaxonLookupEtl } from './inat-taxon-lookup/index';
import { runInaturalistImageEtl } from './inaturalist-images/index';
import { runObisEtl } from './obis/index';
import { runOpenDiveMapEtl } from './opendivemap/index';
import { runOverpassEtl } from './overpass/index';
import { runTavilySpeciesEtl } from './tavily-species/index';
import { runWikimediaImagesEtl } from './wikimedia-images/index';
import { runWormsEtl } from './worms/index';
import { isMainModule } from './shared/cli';
import { createClient } from '@supabase/supabase-js';

/**
 * Run the full OceanLog data ETL pipeline in the correct order.
 *
 * Order is significant: taxonomy first (so GBIF/OBIS occurrences can
 * be linked to species), then dive sites, then occurrences, then the
 * image backfill chain (Wikimedia → iNaturalist → Tavily fallback).
 * Finally we run the open-water reconciliation to mop up sightings
 * that couldn't be linked to a known site.
 */
export async function runAllDataEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting full OceanLog data ETL pipeline');

  // 1. Taxonomy first.
  await runWormsEtl();

  // 2. GBIF taxonomy enrichment (depends on WoRMS having populated the
  // canonical scientific names).
  // await runGbifEtl(); // re-enabled in CI

  // 3. Open dive site sources in parallel.
  await Promise.all([runOpenDiveMapEtl(), runOverpassEtl(), runDiveNumberEtl()]);

  // 4. Apify Google Maps crawl. Last because it is the slowest.
  await runApifyGoogleMapsEtl();

  // 5. GBIF + OBIS occurrences. These link to species via scientific
  // name, and to dive sites via nearby_dive_sites.
  await runGbifEtl();
  await runObisEtl();

  // 6. Post-import reconciliation: create placeholder sites for any
  // sightings that didn't link to a known site within 30 km.
  await runOpenWaterReconciliation();

  // 7. Resolve iNaturalist taxon IDs for species that don't have one
  // yet. This must run BEFORE the image backfills, because
  // inaturalist-images uses inat_taxon_id.
  await runInatTaxonLookupEtl();

  // 8. Image backfills, in increasing cost / decreasing quality.
  await runWikimediaImagesEtl();
  await runInaturalistImageEtl();
  await runTavilySpeciesEtl();

  logger.info(`Full data ETL finished in ${Date.now() - startedAt}ms`);
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
  for (const source of ['gbif', 'obis'] as const) {
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
