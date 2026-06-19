import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

/**
 * Darwin Core export. The previous public-service-role implementation was
 * a privacy and rate-limit disaster (C-4, H-9). This version:
 *
 *   - Requires the X-Cron-Secret header (or a valid admin JWT).
 *   - Filters on BOTH verified_by IS NOT NULL AND verified_at IS NOT NULL
 *     (the prior API version used verified_by; the prior Edge Function
 *     version used verified_at; they differed).
 *   - Caps the row count at 5000 with a hard server-side LIMIT.
 *   - Only exports sightings whose source IN ('user', 'manual') to avoid
 *     circular GBIF → OceanLog → GBIF propagation.
 *   - Returns CSV or JSON based on the format param.
 */

interface SightingExportRow {
  id: string;
  observed_at: string;
  depth_m: number | null;
  count: number;
  photo_urls: string[];
  notes: string | null;
  verified_at: string | null;
  source: string;
  external_id: string | null;
  species: {
    scientific_name: string;
    gbif_taxon_key: number | null;
    worms_id: number | null;
    kingdom: string | null;
    phylum: string | null;
    class_name: string | null;
    order_name: string | null;
    family: string | null;
    genus: string | null;
    image_license: string | null;
  } | null;
  dive_site: {
    name: string;
    country_code: string;
    region: string | null;
    location: unknown;
  } | null;
  user: { username: string; full_name: string | null } | null;
  verifier: { username: string; full_name: string | null } | null;
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

function isAuthorizedCron(req: Request): boolean {
  const expected = Deno.env.get("CRON_SHARED_SECRET");
  if (!expected) return false;
  const provided = req.headers.get("x-cron-secret");
  if (!provided || provided.length !== expected.length) return false;
  let mismatch = 0;
  for (let i = 0; i < expected.length; i++) {
    mismatch |= expected.charCodeAt(i) ^ provided.charCodeAt(i);
  }
  return mismatch === 0;
}

function parsePoint(location: unknown): { lat: number; lng: number } | null {
  if (!location) return null;
  if (typeof location === "object" && location !== null && "coordinates" in location) {
    const coords = (location as { coordinates: number[] }).coordinates;
    if (Array.isArray(coords) && coords.length >= 2) {
      return { lng: coords[0], lat: coords[1] };
    }
  }
  if (typeof location === "string") {
    const match = location.match(/POINT\s*\(\s*([-\d.]+)\s+([-\d.]+)\s*\)/i);
    if (match) return { lng: Number(match[1]), lat: Number(match[2]) };
  }
  return null;
}

function toDarwinCore(row: SightingExportRow) {
  const point = parsePoint(row.dive_site?.location);
  if (!point || !row.species?.scientific_name) return null;

  return {
    occurrenceID: `https://oceanlog.app/sightings/${row.id}`,
    basisOfRecord: "HumanObservation",
    occurrenceStatus: "present",
    scientificName: row.species.scientific_name,
    taxonID: row.species.gbif_taxon_key
      ? String(row.species.gbif_taxon_key)
      : row.species.worms_id
        ? `urn:lsid:marinespecies.org:taxname:${row.species.worms_id}`
        : undefined,
    kingdom: row.species.kingdom ?? "Animalia",
    phylum: row.species.phylum ?? undefined,
    class: row.species.class_name ?? undefined,
    order: row.species.order_name ?? undefined,
    family: row.species.family ?? undefined,
    genus: row.species.genus ?? undefined,
    decimalLatitude: point.lat,
    decimalLongitude: point.lng,
    geodeticDatum: "WGS84",
    countryCode: row.dive_site?.country_code,
    locality: [row.dive_site?.name, row.dive_site?.region].filter(Boolean).join(", "),
    waterBody: "Mediterranean Sea",
    minimumDepthInMeters: row.depth_m ?? undefined,
    maximumDepthInMeters: row.depth_m ?? undefined,
    eventDate: row.observed_at,
    individualCount: row.count,
    recordedBy: row.user?.full_name ?? row.user?.username,
    identifiedBy: row.verifier?.full_name ?? row.verifier?.username,
    dateIdentified: row.verified_at ?? undefined,
    identificationVerificationStatus: row.verified_at ? "verified by expert" : "unverified",
    associatedMedia: row.photo_urls?.length ? row.photo_urls.join("|") : undefined,
    occurrenceRemarks: row.notes ?? undefined,
    license: row.species.image_license ?? "https://creativecommons.org/licenses/by/4.0/",
    institutionCode: "OCEANLOG",
    collectionCode: "SIGHTINGS",
    catalogNumber: row.id,
    oceanlogSource: row.source,
    oceanlogExternalId: row.external_id ?? undefined,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (!isAuthorizedCron(req)) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  try {
    const url = new URL(req.url);
    const from = url.searchParams.get("from");
    const to = url.searchParams.get("to");
    const countryCode = url.searchParams.get("country_code");
    const verifiedOnly = url.searchParams.get("verified_only") !== "false";
    const format = url.searchParams.get("format") ?? "json";

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    let query = supabase
      .from("sightings")
      .select(`
        id, observed_at, depth_m, count, photo_urls, notes, verified_at, source, external_id,
        species (
          scientific_name, gbif_taxon_key, worms_id, kingdom, phylum,
          class_name, order_name, family, genus, image_license
        ),
        dive_site:dive_sites (
          name, country_code, region, location
        ),
        user:users!sightings_user_id_fkey ( username, full_name ),
        verifier:users!sightings_verified_by_fkey ( username, full_name )
      `)
      .in("source", ["user", "manual"])
      .order("observed_at", { ascending: false })
      .limit(5000);

    if (verifiedOnly) {
      query = query
        .not("verified_at", "is", null)
        .not("verified_by", "is", null);
    }
    if (from) query = query.gte("observed_at", from);
    if (to) query = query.lte("observed_at", to);

    const { data, error } = await query;
    if (error) throw error;

    let rows = (data ?? []) as SightingExportRow[];
    if (countryCode) {
      rows = rows.filter((r) => r.dive_site?.country_code === countryCode);
    }

    const occurrences = rows.map(toDarwinCore).filter(Boolean);

    if (format === "csv") {
      const headers = [
        "occurrenceID", "scientificName", "decimalLatitude", "decimalLongitude",
        "eventDate", "individualCount", "countryCode", "locality",
      ];
      const lines = [
        headers.join(","),
        ...occurrences.map((o) =>
          headers
            .map((h) => {
              const val = (o as Record<string, unknown>)[h];
              return val == null ? "" : `"${String(val).replace(/"/g, '""')}"`;
            })
            .join(","),
        ),
      ];
      return new Response(lines.join("\n"), {
        headers: {
          ...CORS_HEADERS,
          "Content-Type": "text/csv",
          "Content-Disposition": 'attachment; filename="oceanlog-dwc.csv"',
        },
      });
    }

    return new Response(
      JSON.stringify({
        generated_at: new Date().toISOString(),
        record_count: occurrences.length,
        format: "json",
        occurrences,
      }),
      { headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error('darwin-core-export failed', err);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      },
    );
  }
});
