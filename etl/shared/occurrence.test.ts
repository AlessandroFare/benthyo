import { describe, expect, it } from 'vitest';
import { normalizeCount, normalizeDepth, normalizeObservedAt } from './occurrence';

describe('normalizeObservedAt', () => {
  it('converts OBIS epoch-millisecond numbers to ISO', () => {
    // 1057017600000 ms = 2003-07-01T00:00:00Z (the exact value that crashed
    // the live OBIS run with "date/time field value out of range").
    expect(normalizeObservedAt(1057017600000)).toBe('2003-07-01T00:00:00.000Z');
  });

  it('converts epoch-millisecond numeric strings', () => {
    expect(normalizeObservedAt('1057017600000')).toBe('2003-07-01T00:00:00.000Z');
  });

  it('handles negative (pre-1970) epoch values', () => {
    const iso = normalizeObservedAt('-1325462400000'); // ~1928
    expect(iso).not.toBeNull();
    expect(new Date(iso as string).getUTCFullYear()).toBe(1928);
  });

  it('passes ISO strings through', () => {
    expect(normalizeObservedAt('2020-05-01T12:00:00Z')).toBe('2020-05-01T12:00:00.000Z');
  });

  it('rejects null, empty, and implausible years', () => {
    expect(normalizeObservedAt(null)).toBeNull();
    expect(normalizeObservedAt('')).toBeNull();
    expect(normalizeObservedAt('not-a-date')).toBeNull();
    expect(normalizeObservedAt(99999999999999999)).toBeNull(); // year > 2100
  });
});

describe('normalizeCount', () => {
  it('rounds fractional abundances to a positive integer', () => {
    // "0.17", "20.0", "1241.24" all triggered "invalid input syntax for type
    // integer" on the live run.
    expect(normalizeCount(0.17)).toBe(1); // rounds to 0 -> clamped to 1
    expect(normalizeCount('20.0')).toBe(20);
    expect(normalizeCount(1241.24)).toBe(1241);
  });

  it('defaults to 1 for missing / non-positive values', () => {
    expect(normalizeCount(undefined)).toBe(1);
    expect(normalizeCount(0)).toBe(1);
    expect(normalizeCount(-5)).toBe(1);
  });
});

describe('normalizeDepth', () => {
  it('keeps non-negative depths', () => {
    expect(normalizeDepth(12.5)).toBe(12.5);
    expect(normalizeDepth(0)).toBe(0);
  });

  it('nulls negative or invalid depths (depth_m >= 0 check)', () => {
    expect(normalizeDepth(-3)).toBeNull();
    expect(normalizeDepth(undefined)).toBeNull();
    expect(normalizeDepth(null)).toBeNull();
  });
});
