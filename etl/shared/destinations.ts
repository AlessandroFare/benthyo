/**
 * Shared dive-destination enumeration, used by dive-site-discovery and
 * dive-map-vision. A "destination" is a town / island / marine park that
 * divers travel to (e.g. "Malapascua", "Dahab", "Tulamben") — the unit at
 * which we then hunt for individual named dive sites.
 */

import { z } from 'zod';
import { generateJson } from './llm';
import type { MarineRegion } from './marine-regions';

/**
 * Human-readable context for each region so the LLM enumerates the right
 * geography. Keyed by MarineRegion.name (see shared/marine-regions.ts).
 */
export const REGION_HINTS: Record<string, string> = {
  caribbean: 'the Caribbean Sea (Cozumel, Bonaire, Roatán, Belize, Cayman Islands, Bahamas, Turks & Caicos)',
  red_sea: 'the Red Sea (Egypt — Sharm el-Sheikh, Dahab, Marsa Alam, Hurghada; Sudan)',
  indian_ocean: 'the tropical Indian Ocean (Maldives, Sri Lanka, Andaman Islands, Thailand — Similan/Phuket)',
  southeast_asia: 'Southeast Asia (Indonesia — Bali, Komodo, Raja Ampat, Lembeh; Philippines — Malapascua, Anilao, Tubbataha; Malaysia — Sipadan)',
  australia_nz: 'Australia & New Zealand (Great Barrier Reef, Ningaloo, Poor Knights Islands)',
  pacific: 'the tropical Pacific (Palau, Micronesia — Chuuk/Truk, Fiji, French Polynesia, Hawaii, Galápagos)',
  mediterranean: 'the Mediterranean Sea (Italy, Malta, Croatia, Greece, Spain, France, Cyprus, Egypt north coast)',
  north_atlantic: 'the North Atlantic (Azores, Canary Islands, Florida, Caribbean fringe, US East Coast wrecks)',
  nordic: 'Nordic & northern European waters (Norway, Iceland — Silfra, Scotland — Scapa Flow)',
  east_africa: 'East Africa & western Indian Ocean (Mozambique, Tanzania — Zanzibar/Mafia, Kenya, South Africa — Sodwana/Aliwal, Seychelles, Mauritius)',
  japan_korea: 'Japan & Korea (Okinawa, Izu Peninsula, Jeju)',
};

export const DestinationsSchema = z.object({
  destinations: z
    .array(
      z.object({
        name: z.string().describe('Dive destination / area, e.g. "Malapascua"'),
        country: z.string().describe('Country name'),
      }),
    )
    .describe('Well-known scuba diving destinations in the region'),
});

export interface Destination {
  name: string;
  country: string;
}

/**
 * Ask the LLM for up to `max` well-known diving destinations in a region.
 * Requires the OpenCode Zen key (callers should check isLlmConfigured()).
 */
export async function enumerateDestinations(
  region: MarineRegion,
  max: number,
): Promise<Destination[]> {
  const hint = REGION_HINTS[region.name] ?? region.name.replace(/_/g, ' ');
  const result = await generateJson(DestinationsSchema, {
    system:
      'You are a scuba-diving domain expert with encyclopedic knowledge of dive travel. ' +
      'You only list REAL, well-documented diving destinations. Never invent places.',
    prompt:
      `List up to ${max} well-known scuba diving destinations or areas in ${hint}. ` +
      'Prefer destinations famous for named dive sites. Return distinct places (towns, islands, ' +
      'marine parks), not individual dive sites.',
    temperature: 0.3,
  });
  return result.destinations.slice(0, max);
}

/**
 * Parse an explicit destination list from an env var, format:
 *   "Malapascua,Philippines;Dahab,Egypt;Tulamben,Indonesia"
 * Returns null when the env var is unset (callers then fall back to the LLM).
 */
export function destinationsFromEnv(envKey: string): Destination[] | null {
  const raw = process.env[envKey];
  if (!raw?.trim()) return null;
  return raw
    .split(';')
    .map((pair) => {
      const [name, country = ''] = pair.split(',').map((s) => s.trim());
      return { name, country };
    })
    .filter((d) => d.name.length > 0);
}
