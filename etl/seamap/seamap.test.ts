import { describe, expect, it } from 'vitest';

const OBIS_API = 'https://api.obis.org/v3';
const MED = 'POLYGON((-6 30, 36 30, 36 46, -6 46, -6 30))';

describe('SEAMAP (OBIS megafauna) integration', () => {
  it('returns real Mediterranean megafauna occurrences for Cetacea', async () => {
    const params = new URLSearchParams({
      geometry: MED,
      scientificname: 'Cetacea',
      size: '5',
      start: '0',
    });
    const response = await fetch(`${OBIS_API}/occurrence?${params}`);
    expect(response.ok).toBe(true);

    const data = (await response.json()) as {
      total: number;
      results: Array<{ id: string; scientificName?: string }>;
    };
    // Real query — must actually return data (the old single-datasetid filter
    // returned 0, which is the bug this source fix addresses).
    expect(data.total).toBeGreaterThan(0);
    expect(data.results.length).toBeGreaterThan(0);
    expect(data.results[0].id).toBeTypeOf('string');
  });

  it('Testudines (sea turtles) query also returns Mediterranean data', async () => {
    const params = new URLSearchParams({
      geometry: MED,
      scientificname: 'Testudines',
      size: '3',
      start: '0',
    });
    const response = await fetch(`${OBIS_API}/occurrence?${params}`);
    const data = (await response.json()) as { total: number; results: unknown[] };
    expect(data.total).toBeGreaterThan(0);
  });

  it('dedups occurrences by id across taxa', () => {
    const byId = new Map<string, { id: string }>();
    [{ id: 'a' }, { id: 'b' }, { id: 'a' }].forEach((o) => byId.set(o.id, o));
    expect([...byId.values()]).toHaveLength(2);
  });
});
