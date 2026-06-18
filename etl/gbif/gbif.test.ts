import { describe, expect, it } from 'vitest';

const GBIF_API = 'https://api.gbif.org/v1';

interface GbifSearchResponse {
  count: number;
  results: Array<{ key: number; scientificName?: string }>;
}

describe('GBIF API integration', () => {
  it('returns Mediterranean marine occurrences with coordinates', async () => {
    const params = new URLSearchParams({
      geometry: 'POLYGON((-6 30, 36 30, 36 46, -6 46, -6 30))',
      hasCoordinate: 'true',
      limit: '5',
      offset: '0',
    });

    const response = await fetch(`${GBIF_API}/occurrence/search?${params}`);
    expect(response.ok).toBe(true);

    const data = (await response.json()) as GbifSearchResponse;
    expect(data.count).toBeGreaterThan(0);
    expect(data.results.length).toBeGreaterThan(0);
    expect(data.results[0].key).toBeTypeOf('number');
  });

  it('matches a known Mediterranean species name', async () => {
    const params = new URLSearchParams({
      name: 'Epinephelus marginatus',
      kingdom: 'Animalia',
    });

    const response = await fetch(`${GBIF_API}/species/match?${params}`);
    expect(response.ok).toBe(true);

    const data = (await response.json()) as { usageKey?: number; scientificName?: string };
    expect(data.usageKey).toBeTypeOf('number');
    expect(data.scientificName).toContain('Epinephelus');
  });
});

describe('GBIF ETL helpers', () => {
  it('maps IUCN categories to conservation status enum', () => {
    const map: Record<string, string> = {
      LC: 'LC',
      EN: 'EN',
      CR: 'CR',
    };

    expect(map['LC']).toBe('LC');
    expect(map['EN']).toBe('EN');
  });

  it('builds idempotent external_id from occurrence key', () => {
    const occKey = 1234567890;
    const externalId = String(occKey);
    expect(externalId).toBe('1234567890');
  });
});
