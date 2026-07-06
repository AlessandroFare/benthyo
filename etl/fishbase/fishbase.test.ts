import { describe, expect, it } from 'vitest';
import { parquetReadObjects } from 'hyparquet';

const BASE = 'https://data.source.coop/cboettig/fishbase/fb/v24.07/parquet';

async function loadParquet<T>(url: string, columns?: string[]): Promise<T[]> {
  const res = await fetch(url);
  expect(res.ok).toBe(true);
  const buffer = await res.arrayBuffer();
  const file = {
    byteLength: buffer.byteLength,
    async slice(s: number, e?: number) {
      return buffer.slice(s, e);
    },
  };
  return (await parquetReadObjects({ file, columns })) as T[];
}

describe('FishBase Parquet species-enrichment source', () => {
  it('exposes real depth range + habitat for a known marine fish', async () => {
    const rows = await loadParquet<{
      Genus: string;
      Species: string;
      DemersPelag: string | null;
      DepthRangeShallow: number | null;
      DepthRangeDeep: number | null;
      Saltwater: number | null;
    }>(`${BASE}/species.parquet`, [
      'Genus',
      'Species',
      'DemersPelag',
      'DepthRangeShallow',
      'DepthRangeDeep',
      'Saltwater',
    ]);
    const tuna = rows.find((r) => r.Genus === 'Thunnus' && r.Species === 'thynnus');
    expect(tuna).toBeDefined();
    expect(tuna?.Saltwater).toBe(1);
    expect(tuna?.DemersPelag).toBeTypeOf('string');
    expect(Number(tuna?.DepthRangeDeep)).toBeGreaterThan(0);
  }, 60000);

  it('provides Italian and Spanish common names in comnames', async () => {
    const rows = await loadParquet<{
      SpecCode: number;
      ComName: string;
      Language: string;
    }>(`${BASE}/comnames.parquet`, ['SpecCode', 'ComName', 'Language']);
    const langs = new Set(rows.map((r) => r.Language));
    expect(langs.has('Italian')).toBe(true);
    expect(langs.has('Spanish')).toBe(true);
    expect(langs.has('English')).toBe(true);
  }, 60000);

  it('builds the marine/brackish/freshwater environment list from flags', () => {
    const flags = (r: { Saltwater?: number; Brack?: number; Fresh?: number }) => {
      const env: string[] = [];
      if (r.Saltwater) env.push('marine');
      if (r.Brack) env.push('brackish');
      if (r.Fresh) env.push('freshwater');
      return env;
    };
    expect(flags({ Saltwater: 1, Brack: 1 })).toEqual(['marine', 'brackish']);
    expect(flags({ Fresh: 1 })).toEqual(['freshwater']);
  });
});
