import { createClient, type SupabaseClient } from '@supabase/supabase-js';

let client: SupabaseClient | null = null;

export function getSupabase(): SupabaseClient {
  if (client) return client;

  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !key) {
    throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required');
  }

  client = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  return client;
}

export interface UpsertResult {
  processed: number;
  upserted: number;
  skipped: number;
  errors: string[];
}

export async function upsertBatch<T extends Record<string, unknown>>(
  table: string,
  rows: T[],
  onConflict: string,
): Promise<UpsertResult> {
  const supabase = getSupabase();
  const result: UpsertResult = {
    processed: rows.length,
    upserted: 0,
    skipped: 0,
    errors: [],
  };

  if (rows.length === 0) return result;

  const chunkSize = 100;
  for (let i = 0; i < rows.length; i += chunkSize) {
    const chunk = rows.slice(i, i + chunkSize);
    const { error } = await supabase
      .from(table)
      .upsert(chunk as unknown as Record<string, unknown>[], {
        onConflict,
        ignoreDuplicates: false,
      });

    if (error) {
      // Batch failed — retry one row at a time to isolate bad rows
      for (const row of chunk) {
        const { error: rowError } = await supabase
          .from(table)
          .upsert(row as unknown as Record<string, unknown>, {
            onConflict,
            ignoreDuplicates: false,
          });

        if (rowError) {
          result.errors.push(`Row "${(row as Record<string, unknown>)[onConflict]}": ${rowError.message}`);
          result.skipped += 1;
        } else {
          result.upserted += 1;
        }
      }
    } else {
      result.upserted += chunk.length;
    }
  }

  return result;
}

export async function fetchExistingKeys(
  table: string,
  column: string,
  values: string[],
): Promise<Set<string>> {
  const supabase = getSupabase();
  const existing = new Set<string>();
  const chunkSize = 200;

  for (let i = 0; i < values.length; i += chunkSize) {
    const chunk = values.slice(i, i + chunkSize);
    const { data, error } = await supabase.from(table).select(column).in(column, chunk);

    if (error) {
      throw new Error(`Failed to fetch existing ${table}.${column}: ${error.message}`);
    }

    for (const row of data ?? []) {
      const value = (row as unknown as Record<string, string>)[column];
      if (value) existing.add(value);
    }
  }

  return existing;
}