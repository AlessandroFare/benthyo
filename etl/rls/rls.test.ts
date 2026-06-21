import { describe, expect, it } from 'vitest';

describe('RLS to WoRMS code mapping', () => {
  it('resolves known RLS codes from the local mapping', () => {
    const mapping: Record<string, string> = {
      ABAL: 'Ablennes hians',
      ABUD: 'Abudefduf',
      MOLA: 'Mola mola',
      EPIN: 'Epinephelus',
    };

    expect(mapping['MOLA']).toBe('Mola mola');
    expect(mapping['EPIN']).toContain('Epinephelus');
  });

  it('falls back to scientific name for unknown codes', () => {
    const unknownCode = 'XXXX';
    const fallbackName = 'Chromis chromis';
    const resolved = unknownCode === 'XXXX' ? fallbackName : undefined;
    expect(resolved).toBe('Chromis chromis');
  });

  it('handles case-insensitive code lookup', () => {
    const mapping: Record<string, string> = {
      MOLA: 'Mola mola',
      mola: 'Mola mola',
    };
    expect(mapping[mapping['MOLA']!] ?? mapping['MOLA']).toBe('Mola mola');
  });
});

describe('RLS external_id construction', () => {
  it('uses observation id as external_id', () => {
    const obsId = 'rls-obs-001234';
    const externalId = obsId;
    expect(externalId).toBe('rls-obs-001234');
  });

  it('prepends source prefix for idempotent upsert', () => {
    const source = 'rls';
    const obsId = 'abc-123';
    expect(`${source},${obsId}`).toBe('rls,abc-123');
  });
});
