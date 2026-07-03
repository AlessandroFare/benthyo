-- Migration 059: site_public_card v2
--
-- Extends the existing `site_public_card` RPC with two additional fields:
--   • `top_species` – JSON array of up to 5 most-frequently sighted species at
--     the site (id, common_name, scientific_name, sighting_count), useful for
--     the embed widget "spotted here" section.
--   • `image_url` – first photo URL from any sighting at this site, used as the
--     embed card's optional hero image.
--
-- The function remains STABLE (read-only) and accessible to anon + authenticated.

CREATE OR REPLACE FUNCTION site_public_card(p_site_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
  SELECT jsonb_build_object(
    'site_id',            ds.id,
    'name',               ds.name,
    'slug',               ds.slug,
    'region',             ds.region,
    'country_code',       ds.country_code,
    'depth_max',          ds.depth_max,
    'difficulty',         ds.difficulty,
    'total_dives', (
      SELECT count(*)::int FROM dive_logs dl WHERE dl.dive_site_id = ds.id
    ),
    'total_species', (
      SELECT count(DISTINCT s.species_id)::int
      FROM sightings s WHERE s.dive_site_id = ds.id
    ),
    'verified_sightings', (
      SELECT count(*)::int FROM sightings s
      WHERE s.dive_site_id = ds.id AND s.verified_by IS NOT NULL
    ),
    'last_dive_at', (
      SELECT max(dl.dive_date) FROM dive_logs dl WHERE dl.dive_site_id = ds.id
    ),
    'avg_depth_m', (
      SELECT round(avg(dl.max_depth_m)::numeric, 1)
      FROM dive_logs dl WHERE dl.dive_site_id = ds.id
    ),
    'avg_visibility_m', (
      SELECT round(avg(sr.visibility_m)::numeric, 1)
      FROM site_reviews sr
      WHERE sr.dive_site_id = ds.id AND sr.visibility_m IS NOT NULL
    ),
    -- ── New in v2 ─────────────────────────────────────────────────────────────
    'top_species', (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'species_id',      sp.id,
            'common_name',     sp.common_name,
            'scientific_name', sp.scientific_name,
            'sighting_count',  agg.cnt
          )
          ORDER BY agg.cnt DESC
        ),
        '[]'::jsonb
      )
      FROM (
        SELECT s.species_id, count(*)::int AS cnt
        FROM sightings s
        WHERE s.dive_site_id = ds.id
          AND s.species_id IS NOT NULL
        GROUP BY s.species_id
        ORDER BY cnt DESC
        LIMIT 5
      ) agg
      JOIN species sp ON sp.id = agg.species_id
    ),
    'image_url', (
      -- First available photo URL (from sighting_photos if it exists, else
      -- falls back to the legacy photo_urls array on sightings).
      SELECT COALESCE(
        (
          SELECT p.public_url
          FROM sighting_photos p
          JOIN sightings s2 ON s2.id = p.sighting_id
          WHERE s2.dive_site_id = ds.id
            AND p.public_url IS NOT NULL
          ORDER BY p.sort_order, p.created_at
          LIMIT 1
        ),
        (
          SELECT (s3.photo_urls)[1]
          FROM sightings s3
          WHERE s3.dive_site_id = ds.id
            AND array_length(s3.photo_urls, 1) > 0
          LIMIT 1
        )
      )
    )
  )
  FROM dive_sites ds
  WHERE ds.id = p_site_id;
$$;

COMMENT ON FUNCTION site_public_card(UUID) IS
  'v2: embeddable public stats card for a dive site. '
  'Returns name, slug, dive counts, species counts, avg depth/vis, '
  'top_species array, and an optional hero image_url. '
  'Safe for anon callers — no PII exposed.';

-- Preserve existing grants
GRANT EXECUTE ON FUNCTION site_public_card(UUID) TO anon, authenticated, service_role;
