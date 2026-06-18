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

function textBetween(xml: string, tag: string): string | null {
  const re = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`, 'i');
  const match = xml.match(re);
  return match?.[1]?.trim() ?? null;
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
  const sampleRe = /<sample[^>]*>([\s\S]*?)<\/sample>/gi;
  let sampleMatch: RegExpExecArray | null;
  while ((sampleMatch = sampleRe.exec(block)) !== null) {
    const sampleXml = sampleMatch[1];
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
  const generator = textBetween(xml, 'generator');
  const dives: ParsedUddfDive[] = [];

  const divesiteRe = /<divesite[^>]*>([\s\S]*?)<\/divesite>/gi;
  let match: RegExpExecArray | null;
  while ((match = divesiteRe.exec(xml)) !== null) {
    const dive = parseDiveBlock(match[1]);
    if (dive) dives.push(dive);
  }

  if (dives.length === 0) {
    const diveRe = /<dive[^>]*>([\s\S]*?)<\/dive>/gi;
    while ((match = diveRe.exec(xml)) !== null) {
      const dive = parseDiveBlock(match[1]);
      if (dive) dives.push(dive);
    }
  }

  return { dives, generator };
}
