/**
 * Minimal UDDF / UDCF XML parser for Suunto, Shearwater, Garmin exports.
 */

export interface UddfProfileSample {
  timeSec: number;
  depthM: number;
}

export interface ParsedUddfDive {
  siteName: string | null;
  diveDate: string;
  maxDepthM: number;
  durationMin: number;
  avgDepthM?: number;
  waterTempC?: number;
  profileSamples: UddfProfileSample[];
}

export interface UddfImportResult {
  dives: ParsedUddfDive[];
  generator: string | null;
}

const MAX_XML_CHARS = 2_000_000;
const MAX_DIVE_BLOCKS = 500;
const MAX_PROFILE_SAMPLES = 5_000;

function textBetween(xml: string, tag: string): string | null {
  const open = `<${tag}`;
  const start = xml.indexOf(open);
  if (start === -1) return null;
  const contentStart = xml.indexOf('>', start);
  if (contentStart === -1) return null;
  const close = `</${tag}>`;
  const end = xml.indexOf(close, contentStart + 1);
  if (end === -1) return null;
  return xml.slice(contentStart + 1, end).trim();
}

function extractBlocks(xml: string, tag: string, maxBlocks: number): string[] {
  const blocks: string[] = [];
  const open = `<${tag}`;
  const close = `</${tag}>`;
  let searchFrom = 0;
  while (blocks.length < maxBlocks) {
    const start = xml.indexOf(open, searchFrom);
    if (start === -1) break;
    const contentStart = xml.indexOf('>', start);
    if (contentStart === -1) break;
    const end = xml.indexOf(close, contentStart + 1);
    if (end === -1) break;
    blocks.push(xml.slice(contentStart + 1, end));
    searchFrom = end + close.length;
  }
  return blocks;
}

function numeric(text: string | null): number | null {
  if (text == null) return null;
  const n = Number.parseFloat(text.replace(',', '.'));
  return Number.isFinite(n) ? n : null;
}

function parseDate(raw: string | null): string | null {
  if (!raw) return null;
  const iso = raw.trim();
  if (/^\d{4}-\d{2}-\d{2}/.test(iso)) return iso.slice(0, 10);
  const dmy = iso.match(/^(\d{2})\.(\d{2})\.(\d{4})/);
  if (dmy) return `${dmy[3]}-${dmy[2]}-${dmy[1]}`;
  return null;
}

function parseDiveBlock(block: string): ParsedUddfDive | null {
  const siteName =
    textBetween(block, 'name') ??
    textBetween(block, 'site') ??
    textBetween(block, 'location');

  const datetime =
    textBetween(block, 'datetime') ??
    textBetween(block, 'date') ??
    textBetween(block, 'entrytime');

  const diveDate = parseDate(datetime);
  if (!diveDate) return null;

  const maxDepthM =
    numeric(textBetween(block, 'greatestdepth')) ??
    numeric(textBetween(block, 'maxdepth')) ??
    numeric(textBetween(block, 'depth')) ??
    0;

  const durationSec =
    numeric(textBetween(block, 'duration')) ??
    numeric(textBetween(block, 'diveduration')) ??
    0;

  const durationMin = Math.max(1, Math.round(durationSec / 60));

  const avgDepthM =
    numeric(textBetween(block, 'averagedepth')) ??
    numeric(textBetween(block, 'meandepth')) ??
    undefined;

  const waterTempC =
    numeric(textBetween(block, 'watertemperature')) ??
    numeric(textBetween(block, 'temperature')) ??
    undefined;

  const profileSamples: UddfProfileSample[] = [];
  for (const sampleXml of extractBlocks(block, 'sample', MAX_PROFILE_SAMPLES)) {
    const timeSec =
      numeric(textBetween(sampleXml, 'divetime')) ??
      numeric(textBetween(sampleXml, 'time')) ??
      null;
    const depthM =
      numeric(textBetween(sampleXml, 'depth')) ??
      numeric(textBetween(sampleXml, 'penetration')) ??
      null;
    if (timeSec != null && depthM != null) {
      profileSamples.push({ timeSec, depthM });
    }
  }

  return {
    siteName,
    diveDate,
    maxDepthM: Math.max(0, maxDepthM),
    durationMin,
    avgDepthM,
    waterTempC,
    profileSamples,
  };
}

export function parseUddfXml(xml: string): UddfImportResult {
  if (xml.length > MAX_XML_CHARS) {
    throw new Error('UDDF file exceeds maximum supported size');
  }

  const generator = textBetween(xml, 'generator');
  const dives: ParsedUddfDive[] = [];

  for (const block of extractBlocks(xml, 'divesite', MAX_DIVE_BLOCKS)) {
    const dive = parseDiveBlock(block);
    if (dive) dives.push(dive);
  }

  if (dives.length === 0) {
    for (const block of extractBlocks(xml, 'dive', MAX_DIVE_BLOCKS)) {
      const dive = parseDiveBlock(block);
      if (dive) dives.push(dive);
    }
  }

  return { dives, generator };
}
