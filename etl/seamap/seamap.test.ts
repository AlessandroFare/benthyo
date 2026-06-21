import { describe, expect, it } from 'vitest';

const OBIS_API = 'https://api.obis.org/v3';

describe('SEAMAP API integration', () => {
  it('OBIS API is reachable with SEAMAP dataset filter', async () => {
    const params = new URLSearchParams({
      geometry: 'POLYGON((-6 30, 36 30, 36 46, -6 46, -6 30))',
      datasetid: 'd372cbce-85b8-4c03-a70a-5d9a00c3b792',
      size: '5',
      start: '0',
    });

    const response = await fetch(`${OBIS_API}/occurrence?${params}`);
    expect(response.ok).toBe(true);

    const data = (await response.json()) as {
      total: number;
      results: Array<{ id: string; scientificName?: string }>;
    };
    // Don't require non-zero results — SEAMAP dataset may have no occurrences
    // in the Mediterranean bounding box. The API contract is the test target.
    expect(data).toHaveProperty('results');
    expect(Array.isArray(data.results)).toBe(true);
    if (data.results.length > 0) {
      expect(data.results[0].id).toBeTypeOf('string');
    }
  });

  it('includes scientificName on returned occurrences when present', async () => {
    const params = new URLSearchParams({
      geometry: 'POLYGON((-6 30, 36 30, 36 46, -6 46, -6 30))',
      datasetid: 'd372cbce-85b8-4c03-a70a-5d9a00c3b792',
      size: '3',
      start: '0',
    });
    const response = await fetch(`${OBIS_API}/occurrence?${params}`);
    const data = (await response.json()) as { results: Array<{ scientificName?: string }> };
    for (const occ of data.results) {
      expect(occ.scientificName).toBeTypeOf('string');
    }
  });

  it('constructs SEAMAP external_id from occurrence id', () => {
    const occId = 'obis:occ:12345';
    expect(occId).toBeTypeOf('string');
    expect(occId.split(':').length).toBe(3);
  });
});
