import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { RateLimiter } from '../shared/rate-limiter';
import {
  geographyPoint,
  normalizeAccessType,
  normalizeCountryCode,
  normalizeDifficulty,
  normalizeSiteType,
  slugify,
  uniqueSlug,
  type DiveSiteRow,
} from '../shared/dive-site-utils';
import { upsertBatch } from '../shared/supabase';
import { isMainModule } from '../shared/cli';

/**
 * Wikidata SPARQL dive-site ETL.
 *
 * High-correctness, zero-budget source: Wikidata carries hand-curated, exact
 * WGS-84 coordinates (P625) for tens of thousands of shipwrecks, reefs, and
 * other underwater features worldwide, each with multilingual labels and, for
 * many, an ISO country code (via P17 → P297). Unlike heuristic crawls, every
 * row here is human-verified structured data.
 *
 * We query the public SPARQL endpoint (no API key) once per feature category,
 * mapping each Wikidata class to a canonical `site_type`. Failures per category
 * are isolated so a single timeout does not lose the other categories' rows.
 */

const WIKIDATA_SPARQL =
  process.env.WIKIDATA_SPARQL_URL ?? 'https://query.wikidata.org/sparql';

// A descriptive UA is required by the Wikidata Query Service usage policy.
const USER_AGENT =
  process.env.WIKIDATA_USER_AGENT ??
  'BenthyoETL/1.0 (https://benthyo.com; dive-site enrichment)';

// Wikidata is generous but polite spacing avoids throttling. The service
// also enforces a 60s per-query timeout, handled per category below.
const limiter = new RateLimiter({ minIntervalMs: 1500, maxRetries: 4, baseBackoffMs: 2000 });

interface WikidataCategory {
  /** Wikidata QID whose instances (incl. subclasses) we ingest. */
  qid: string;
  /** Canonical dive_sites.site_type for this category. */
  siteType: string;
  label: string;
}

/**
 * Feature classes worth mapping to dive sites. Each is queried via
 * `P31/P279*` (instance-of, following subclass chains) intersected with a
 * coordinate (P625), so only georeferenced features are ingested.
 */
const CATEGORIES: WikidataCategory[] = [
  { qid: 'Q852190', siteType: 'wreck', label: 'shipwreck' },
  { qid: 'Q206137', siteType: 'reef', label: 'coral reef' },
  { qid: 'Q184358', siteType: 'reef', label: 'reef' },
  { qid: 'Q1435205', siteType: 'cave', label: 'cenote' },
  { qid: 'Q740445', siteType: 'cave', label: 'blue hole' },
  { qid: 'Q271669', siteType: 'pinnacle', label: 'seamount' },
];

interface SparqlBinding {
  item: { value: string };
  coord: { value: string };
  label_en?: { value: string };
  label_it?: { value: string };
  label_es?: { value: string };
  desc?: { value: string };
  iso?: { value: string };
  depth?: { value: string };
}

interface SparqlResponse {
  results: { bindings: SparqlBinding[] };
}

const CATEGORY_LIMIT = Number(process.env.WIKIDATA_CATEGORY_LIMIT ?? 5000);

function buildQuery(category: WikidataCategory): string {
  // Note: FILTER inside OPTIONAL binds the language-specific label only.
  return `
SELECT ?item ?coord ?label_en ?label_it ?label_es ?desc ?iso ?depth WHERE {
  ?item wdt:P31/wdt:P279* wd:${category.qid} .
  ?item wdt:P625 ?coord .
  OPTIONAL { ?item wdt:P17 ?country. ?country wdt:P297 ?iso. }
  OPTIONAL { ?item wdt:P4511 ?depth. }
  OPTIONAL { ?item rdfs:label ?label_en. FILTER(LANG(?label_en) = "en") }
  OPTIONAL { ?item rdfs:label ?label_it. FILTER(LANG(?label_it) = "it") }
  OPTIONAL { ?item rdfs:label ?label_es. FILTER(LANG(?label_es) = "es") }
  OPTIONAL { ?item schema:description ?desc. FILTER(LANG(?desc) = "en") }
}
LIMIT ${CATEGORY_LIMIT}
`;
}

/** Parse a WKT `Point(lon lat)` literal into [lon, lat]. */
function parsePoint(wkt: string): [number, number] | null {
  const match = /Point\(\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s*\)/i.exec(wkt);
  if (!match) return null;
  const lon = Number(match[1]);
  const lat = Number(match[2]);
  if (!Number.isFinite(lon) || !Number.isFinite(lat)) return null;
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
  return [lon, lat];
}

async function fetchCategory(category: WikidataCategory): Promise<SparqlBinding[]> {
  const query = buildQuery(category);
  logger.info(`Wikidata query: ${category.label} (${category.qid})`);

  const response = await limiter.fetch(WIKIDATA_SPARQL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      Accept: 'application/sparql-results+json',
      'User-Agent': USER_AGENT,
    },
    body: `query=${encodeURIComponent(query)}`,
  });

  if (!response.ok) {
    const body = await response.text().catch(() => '');
    throw new Error(`Wikidata SPARQL error (${category.label}): HTTP ${response.status} ${body.slice(0, 160)}`);
  }

  const data = (await response.json()) as SparqlResponse;
  const bindings = data.results?.bindings ?? [];
  logger.info(`Wikidata ${category.label}: ${bindings.length} bindings`);
  return bindings;
}

function mapBinding(
  binding: SparqlBinding,
  category: WikidataCategory,
  seenSlugs: Set<string>,
): DiveSiteRow | null {
  const point = parsePoint(binding.coord.value);
  if (!point) return null;
  const [lon, lat] = point;

  const name = binding.label_en?.value ?? binding.label_it?.value ?? binding.label_es?.value;
  // Skip unlabeled items (bare QID names are useless in the UI).
  if (!name) return null;

  const qid = binding.item.value.replace('http://www.wikidata.org/entity/', '');
  const slug = uniqueSlug(slugify(name), qid.toLowerCase(), seenSlugs);

  const description = binding.desc?.value ?? null;
  const rawDepth = Number(binding.depth?.value);
  const depthMax = Number.isFinite(rawDepth) && rawDepth > 0 ? rawDepth : 30;

  return {
    name,
    slug,
    description,
    location: geographyPoint(lon, lat),
    country_code: normalizeCountryCode(binding.iso?.value),
    region: null,
    depth_min: 0,
    depth_max: depthMax,
    difficulty: normalizeDifficulty(undefined, description ?? ''),
    site_type: normalizeSiteType(category.siteType),
    access_type: normalizeAccessType(undefined, description ?? ''),
    verified: false,
    metadata: {
      source: 'wikidata',
      wikidata_id: qid,
      wikidata_class: category.qid,
      category: category.label,
      name_it: binding.label_it?.value ?? null,
      name_es: binding.label_es?.value ?? null,
      depth_m: Number.isFinite(rawDepth) && rawDepth > 0 ? rawDepth : null,
    },
  };
}

export async function runWikidataEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting Wikidata SPARQL dive-site ETL');

  const seenSlugs = new Set<string>();
  const seenItems = new Set<string>();
  const siteRows: DiveSiteRow[] = [];
  const errors: string[] = [];
  let processed = 0;

  for (const category of CATEGORIES) {
    try {
      const bindings = await fetchCategory(category);
      for (const binding of bindings) {
        processed += 1;
        // Dedup by QID across categories (an item can carry multiple coords /
        // classes; keep the first occurrence).
        const qid = binding.item.value;
        if (seenItems.has(qid)) continue;
        seenItems.add(qid);
        const row = mapBinding(binding, category, seenSlugs);
        if (row) siteRows.push(row);
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      errors.push(`${category.label}: ${message}`);
      logger.warn(`Wikidata category failed: ${category.label}`, { error: message });
    }
  }

  const result = await upsertBatch(
    'dive_sites',
    siteRows as unknown as Record<string, unknown>[],
    'slug',
  );

  logJobSummary('wikidata', {
    processed,
    upserted: result.upserted,
    skipped: result.skipped,
    errors: [...errors, ...result.errors],
  });

  logger.info(`Wikidata ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runWikidataEtl().catch((err) => {
    logger.error('Wikidata ETL failed', {
      error: err instanceof Error ? err.message : String(err),
    });
    process.exit(1);
  });
}
