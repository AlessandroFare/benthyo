import { describe, expect, it } from 'vitest';

const SPARQL = 'https://query.wikidata.org/sparql';
const UA = 'BenthyoETL/1.0 (test)';

async function runQuery(query: string) {
  const res = await fetch(SPARQL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      Accept: 'application/sparql-results+json',
      'User-Agent': UA,
    },
    body: `query=${encodeURIComponent(query)}`,
  });
  expect(res.ok).toBe(true);
  return (await res.json()) as { results: { bindings: Array<Record<string, { value: string }>> } };
}

describe('Wikidata SPARQL dive-site source', () => {
  it('returns georeferenced shipwrecks with labels', async () => {
    const data = await runQuery(`
      SELECT ?item ?coord ?label_en WHERE {
        ?item wdt:P31/wdt:P279* wd:Q852190 .
        ?item wdt:P625 ?coord .
        OPTIONAL { ?item rdfs:label ?label_en. FILTER(LANG(?label_en) = "en") }
      } LIMIT 5
    `);
    const bindings = data.results.bindings;
    expect(bindings.length).toBeGreaterThan(0);
    expect(bindings[0].coord.value).toMatch(/^Point\(/i);
  }, 30000);

  it('resolves ISO country codes via P17 → P297', async () => {
    const data = await runQuery(`
      SELECT ?item ?iso WHERE {
        ?item wdt:P31/wdt:P279* wd:Q852190 .
        ?item wdt:P625 ?coord .
        ?item wdt:P17 ?country. ?country wdt:P297 ?iso.
      } LIMIT 3
    `);
    expect(data.results.bindings.length).toBeGreaterThan(0);
    expect(data.results.bindings[0].iso.value).toMatch(/^[A-Z]{2}$/);
  }, 30000);

  it('parses a WKT Point literal into [lon, lat]', () => {
    const parsePoint = (wkt: string): [number, number] | null => {
      const m = /Point\(\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s*\)/i.exec(wkt);
      if (!m) return null;
      return [Number(m[1]), Number(m[2])];
    };
    expect(parsePoint('Point(16.253 -28.47472)')).toEqual([16.253, -28.47472]);
    expect(parsePoint('not a point')).toBeNull();
  });
});
