#!/usr/bin/env node
/**
 * Benthyo MCP server — exposes public dive data as tools for LLM agents.
 *
 * Run: BENTHYO_API_URL=http://localhost:3000/api/v1 node index.js
 */
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';

const API = process.env.BENTHYO_API_URL ?? 'http://localhost:3000/api/v1';

async function apiGet(path) {
  const res = await fetch(`${API}${path}`);
  if (!res.ok) throw new Error(`API ${res.status}: ${path}`);
  const body = await res.json();
  return body.data ?? body;
}

const server = new McpServer({
  name: 'benthyo',
  version: '0.1.0',
});

server.tool(
  'search_sites',
  'Search dive sites by region keyword',
  { region: z.string().optional(), q: z.string().optional() },
  async ({ region, q }) => {
    const params = new URLSearchParams({ limit: '10' });
    if (q) params.set('q', q);
    if (region) params.set('region', region);
    const sites = await apiGet(`/dive-sites?${params}`);
    return {
      content: [{ type: 'text', text: JSON.stringify(sites, null, 2) }],
    };
  },
);

server.tool(
  'get_site_card',
  'Embeddable stats for a dive site (dives, species, last dive)',
  { slug: z.string() },
  async ({ slug }) => {
    const card = await apiGet(`/public/sites/${slug}/card`);
    return {
      content: [{ type: 'text', text: JSON.stringify(card, null, 2) }],
    };
  },
);

server.tool(
  'get_prep_card',
  'Pre-dive briefing: conditions, reviews, recent species',
  { slug: z.string() },
  async ({ slug }) => {
    const prep = await apiGet(`/public/sites/${slug}/prep-card`);
    return {
      content: [{ type: 'text', text: JSON.stringify(prep, null, 2) }],
    };
  },
);

server.tool(
  'get_species_phenology',
  'Monthly sighting counts for a species (user-reported heatmap)',
  { species_id: z.string(), site_id: z.string().optional() },
  async ({ species_id, site_id }) => {
    const params = site_id ? `?site_id=${site_id}` : '';
    const species = await apiGet(`/species/${species_id}${params}`);
    return {
      content: [{ type: 'text', text: JSON.stringify(species, null, 2) }],
    };
  },
);

server.tool(
  'get_public_logbook',
  'Public verifiable logbook for a diver username',
  { username: z.string() },
  async ({ username }) => {
    const logbook = await apiGet(`/users/${username}/logbook`);
    return {
      content: [{ type: 'text', text: JSON.stringify(logbook, null, 2) }],
    };
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
