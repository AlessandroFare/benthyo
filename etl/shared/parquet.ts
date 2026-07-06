import { parquetReadObjects } from 'hyparquet';
import { logger } from './logger';

/**
 * Minimal helper for reading the static Parquet snapshots that back
 * FishBase / SeaLifeBase (and any other columnar open-data source).
 *
 * FishBase no longer exposes a REST API — the old `fishbase.ropensci.org`
 * host is dead. The canonical distribution is now a set of static Parquet
 * table dumps hosted on source.coop (see etl/fishbase/index.ts). We read them
 * with `hyparquet`, a dependency-free pure-JS Parquet reader, so the ETL stays
 * "zero budget" (no API keys, no native/duckdb dependency).
 *
 * The whole file is downloaded into memory once and parsed with column
 * projection so only the fields we actually need are materialised. The FishBase
 * tables we use are modest (species ~5MB, comnames ~17MB), well within a
 * nightly ETL's memory budget.
 */

/** An in-memory ArrayBuffer wrapped as the AsyncBuffer hyparquet expects. */
function asAsyncBuffer(buffer: ArrayBuffer) {
  return {
    byteLength: buffer.byteLength,
    async slice(start: number, end?: number): Promise<ArrayBuffer> {
      return buffer.slice(start, end);
    },
  };
}

/**
 * Download a Parquet file and return its rows as plain objects. `columns`
 * projects to only the named fields, which dramatically reduces memory for
 * wide tables (comnames has 35 columns; we only need five).
 */
export async function readParquet<T = Record<string, unknown>>(
  url: string,
  columns?: string[],
): Promise<T[]> {
  const started = Date.now();
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Parquet fetch failed: HTTP ${response.status} for ${url}`);
  }
  const buffer = await response.arrayBuffer();
  const file = asAsyncBuffer(buffer);
  const rows = (await parquetReadObjects({ file, columns })) as T[];
  logger.info(
    `Read ${rows.length} rows from parquet (${(buffer.byteLength / 1e6).toFixed(1)}MB) in ${
      Date.now() - started
    }ms`,
    { url },
  );
  return rows;
}
