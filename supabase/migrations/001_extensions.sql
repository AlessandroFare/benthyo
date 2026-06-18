-- Migration 001: Enable required Postgres extensions.
-- PostGIS is mandatory for GEOGRAPHY types and spatial indexes.
-- pg_trgm enables fuzzy text matching in full-text search.
-- citext provides case-insensitive email-like fields.
-- btree_gin allows combining btree and GIN operators in a single index.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS btree_gin;
