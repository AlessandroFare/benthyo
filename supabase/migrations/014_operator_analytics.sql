-- Migration 014: Operator analytics RPCs for B2B dashboard.
-- Depth histogram, activity heatmap, species diversity, retention cohorts,
-- dives-by-site chart, and recent activity feed.

CREATE OR REPLACE FUNCTION operator_depth_histogram(p_operator_id UUID)
RETURNS TABLE (
  depth_range TEXT,
  count INTEGER
) LANGUAGE sql STABLE AS $$
  SELECT
    CASE
      WHEN sg.depth_m IS NULL THEN 'unknown'
      WHEN sg.depth_m < 10 THEN '0-10m'
      WHEN sg.depth_m < 20 THEN '10-20m'
      WHEN sg.depth_m < 30 THEN '20-30m'
      WHEN sg.depth_m < 40 THEN '30-40m'
      ELSE '40m+'
    END AS depth_range,
    count(*)::int AS count
  FROM sightings sg
  JOIN operator_dive_sites ods ON ods.dive_site_id = sg.dive_site_id
  WHERE ods.operator_id = p_operator_id
  GROUP BY
    CASE
      WHEN sg.depth_m IS NULL THEN 'unknown'
      WHEN sg.depth_m < 10 THEN '0-10m'
      WHEN sg.depth_m < 20 THEN '10-20m'
      WHEN sg.depth_m < 30 THEN '20-30m'
      WHEN sg.depth_m < 40 THEN '30-40m'
      ELSE '40m+'
    END
  ORDER BY MIN(sg.depth_m) NULLS LAST;
$$;

CREATE OR REPLACE FUNCTION operator_activity_heatmap(p_operator_id UUID)
RETURNS TABLE (
  day INTEGER,
  hour INTEGER,
  value INTEGER
) LANGUAGE sql STABLE AS $$
  SELECT
    extract(dow from dl.dive_date)::int AS day,
    coalesce(extract(hour from dl.entry_time)::int, 12) AS hour,
    count(*)::int AS value
  FROM dive_logs dl
  JOIN operator_dive_sites ods ON ods.dive_site_id = dl.dive_site_id
  WHERE ods.operator_id = p_operator_id
    AND dl.dive_date >= (now() - interval '90 days')
  GROUP BY 1, 2;
$$;

CREATE OR REPLACE FUNCTION operator_species_diversity(p_operator_id UUID)
RETURNS TABLE (
  family TEXT,
  count INTEGER,
  percentage NUMERIC
) LANGUAGE sql STABLE AS $$
  WITH family_counts AS (
    SELECT
      coalesce(s.family, 'Unknown') AS family,
      count(DISTINCT s.id)::int AS cnt
    FROM sightings sg
    JOIN operator_dive_sites ods ON ods.dive_site_id = sg.dive_site_id
    JOIN species s ON s.id = sg.species_id
    WHERE ods.operator_id = p_operator_id
    GROUP BY coalesce(s.family, 'Unknown')
  ),
  total AS (
    SELECT sum(cnt)::numeric AS t FROM family_counts
  )
  SELECT
    fc.family,
    fc.cnt AS count,
    round((fc.cnt / nullif(t.t, 0)) * 100, 1) AS percentage
  FROM family_counts fc, total t
  ORDER BY fc.cnt DESC
  LIMIT 12;
$$;

CREATE OR REPLACE FUNCTION operator_customer_retention(p_operator_id UUID)
RETURNS TABLE (
  cohort TEXT,
  month_0 NUMERIC,
  month_1 NUMERIC,
  month_2 NUMERIC,
  month_3 NUMERIC
) LANGUAGE sql STABLE AS $$
  WITH first_dive AS (
    SELECT
      dl.user_id,
      date_trunc('month', min(dl.dive_date))::date AS cohort_month
    FROM dive_logs dl
    JOIN operator_dive_sites ods ON ods.dive_site_id = dl.dive_site_id
    WHERE ods.operator_id = p_operator_id
    GROUP BY dl.user_id
  ),
  cohorts AS (
    SELECT cohort_month, count(*)::numeric AS size
    FROM first_dive
    WHERE cohort_month >= date_trunc('month', now() - interval '6 months')
    GROUP BY cohort_month
  )
  SELECT
    to_char(c.cohort_month, 'YYYY-MM') AS cohort,
    100.0 AS month_0,
    round(
      count(DISTINCT fd.user_id) FILTER (
        WHERE EXISTS (
          SELECT 1 FROM dive_logs dl2
          JOIN operator_dive_sites ods2 ON ods2.dive_site_id = dl2.dive_site_id
          WHERE ods2.operator_id = p_operator_id
            AND dl2.user_id = fd.user_id
            AND date_trunc('month', dl2.dive_date) = c.cohort_month + interval '1 month'
        )
      ) / nullif(c.size, 0) * 100, 1
    ) AS month_1,
    round(
      count(DISTINCT fd.user_id) FILTER (
        WHERE EXISTS (
          SELECT 1 FROM dive_logs dl2
          JOIN operator_dive_sites ods2 ON ods2.dive_site_id = dl2.dive_site_id
          WHERE ods2.operator_id = p_operator_id
            AND dl2.user_id = fd.user_id
            AND date_trunc('month', dl2.dive_date) = c.cohort_month + interval '2 months'
        )
      ) / nullif(c.size, 0) * 100, 1
    ) AS month_2,
    round(
      count(DISTINCT fd.user_id) FILTER (
        WHERE EXISTS (
          SELECT 1 FROM dive_logs dl2
          JOIN operator_dive_sites ods2 ON ods2.dive_site_id = dl2.dive_site_id
          WHERE ods2.operator_id = p_operator_id
            AND dl2.user_id = fd.user_id
            AND date_trunc('month', dl2.dive_date) = c.cohort_month + interval '3 months'
        )
      ) / nullif(c.size, 0) * 100, 1
    ) AS month_3
  FROM cohorts c
  JOIN first_dive fd ON fd.cohort_month = c.cohort_month
  GROUP BY c.cohort_month, c.size
  ORDER BY c.cohort_month;
$$;

CREATE OR REPLACE FUNCTION operator_dives_by_site(p_operator_id UUID)
RETURNS TABLE (
  site_id UUID,
  name TEXT,
  dive_count INTEGER
) LANGUAGE sql STABLE AS $$
  SELECT
    ds.id AS site_id,
    ds.name,
    count(*)::int AS dive_count
  FROM dive_logs dl
  JOIN operator_dive_sites ods ON ods.dive_site_id = dl.dive_site_id
  JOIN dive_sites ds ON ds.id = dl.dive_site_id
  WHERE ods.operator_id = p_operator_id
    AND dl.dive_date >= (now() - interval '12 months')
  GROUP BY ds.id, ds.name
  ORDER BY dive_count DESC
  LIMIT 10;
$$;

COMMENT ON FUNCTION operator_depth_histogram IS 'Depth bucket counts for operator site sightings.';
COMMENT ON FUNCTION operator_activity_heatmap IS 'Dive activity by day-of-week and hour for heatmap UI.';