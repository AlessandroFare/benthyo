import 'dotenv/config';
import { logger, logJobSummary } from '../shared/logger';
import { RateLimiter } from '../shared/rate-limiter';
import { getSupabase, upsertBatch } from '../shared/supabase';
import { isMainModule } from '../shared/cli';

const WORMS_API = 'https://www.marinespecies.org/rest';

interface WormsAphiaRecord {
  AphiaID: number;
  scientificname: string;
  valid_AphiaID?: number;
  valid_name?: string;
  kingdom?: string;
  phylum?: string;
  class?: string;
  order?: string;
  family?: string;
  genus?: string;
  status?: string;
}

interface WormsVernacular {
  vernacular: string;
  language_code?: string;
}

const limiter = new RateLimiter({ minIntervalMs: 150 });

async function searchByScientificName(name: string): Promise<WormsAphiaRecord | null> {
  const params = new URLSearchParams({ scientificname: name });
  const url = `${WORMS_API}/AphiaRecordsByName/${encodeURIComponent(name)}?${params}`;
  try {
    const results = await limiter.fetchJson<WormsAphiaRecord[]>(url);
    if (results.length === 0) return null;
    const accepted = results.find((r) => r.status === 'accepted');
    return accepted ?? results[0];
  } catch {
    return null;
  }
}

async function fetchVernaculars(aphiaId: number): Promise<WormsVernacular[]> {
  const url = `${WORMS_API}/AphiaRecordByAphiaID/${aphiaId}/vernaculars`;
  try {
    return await limiter.fetchJson<WormsVernacular[]>(url);
  } catch {
    return [];
  }
}

function pickVernacular(vernaculars: WormsVernacular[], lang: string): string | undefined {
  return vernaculars.find((v) => v.language_code?.toLowerCase() === lang)?.vernacular;
}

export async function runWormsEtl(): Promise<void> {
  const startedAt = Date.now();
  logger.info('Starting WoRMS species taxonomy ETL');

  const supabase = getSupabase();

  const { data: species, error } = await supabase
    .from('species')
    .select('id, scientific_name, worms_id')
    .is('worms_id', null)
    .limit(500);

  if (error) {
    throw new Error(`Failed to load species: ${error.message}`);
  }

  if (!species || species.length === 0) {
    logger.info('No species missing worms_id — nothing to do');
    logJobSummary('worms', { processed: 0, upserted: 0, skipped: 0, errors: [] });
    return;
  }

  logger.info(`WoRMS: looking up ${species.length} species without worms_id`);

  const speciesRows: Record<string, unknown>[] = [];
  const errors: string[] = [];

  for (const sp of species) {
    const record = await searchByScientificName(sp.scientific_name);
    if (!record) {
      errors.push(`${sp.scientific_name}: not found on WoRMS`);
      continue;
    }

    let vernaculars: WormsVernacular[] = [];
    try {
      vernaculars = await fetchVernaculars(record.AphiaID);
    } catch {
      // non-fatal
    }

    speciesRows.push({
      scientific_name: sp.scientific_name,
      worms_id: record.AphiaID,
      kingdom: record.kingdom ?? 'Animalia',
      phylum: record.phylum,
      class_name: record.class,
      order_name: record.order,
      family: record.family,
      genus: record.genus,
      common_name: pickVernacular(vernaculars, 'eng') ?? pickVernacular(vernaculars, 'en'),
      common_name_it: pickVernacular(vernaculars, 'ita') ?? pickVernacular(vernaculars, 'it'),
      common_name_es: pickVernacular(vernaculars, 'spa') ?? pickVernacular(vernaculars, 'es'),
      metadata: {
        source: 'worms',
        valid_aphia_id: record.valid_AphiaID,
        valid_name: record.valid_name,
      },
    });
  }

  const result = await upsertBatch('species', speciesRows, 'scientific_name');

  logJobSummary('worms', {
    processed: speciesRows.length,
    upserted: result.upserted,
    skipped: result.skipped,
    errors: [...result.errors, ...errors],
  });

  logger.info(`WoRMS ETL finished in ${Date.now() - startedAt}ms`);
}

if (isMainModule(import.meta.url)) {
  runWormsEtl().catch((err) => {
    logger.error('WoRMS ETL failed', { error: err instanceof Error ? err.message : String(err) });
    process.exit(1);
  });
}
