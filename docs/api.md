# API Reference

Benthyo exposes a NestJS REST API and Supabase RPC functions. All responses use the `@benthyo/types` DTO shapes.

## Base URLs

| Environment | URL |
|-------------|-----|
| Local | `http://localhost:3000` |
| Production | `https://api.benthyo.com` |

Supabase RPCs are available at `{SUPABASE_URL}/rest/v1/rpc/{function_name}`.

## Authentication

Protected endpoints require a Supabase JWT in the `Authorization` header:

```
Authorization: Bearer <supabase_access_token>
```

## Response envelope

### Success

```json
{
  "data": { ... }
}
```

### Paginated list

```json
{
  "data": [ ... ],
  "meta": {
    "page": 1,
    "page_size": 20,
    "total": 142,
    "total_pages": 8,
    "has_next": true,
    "has_prev": false
  }
}
```

### Error

```json
{
  "message": "Species not found",
  "statusCode": 404,
  "code": "SPECIES_NOT_FOUND"
}
```

## REST endpoints

### Dive sites

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/dive-sites` | List sites (filter by country, difficulty, type) |
| GET | `/v1/dive-sites/:slug` | Site detail |
| GET | `/v1/dive-sites/nearby` | Sites within radius (`lat`, `lng`, `radius_km`) |
| POST | `/v1/dive-sites` | Create site (authenticated) |

### Species

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/species` | Search catalog |
| GET | `/v1/species/:id` | Species detail |
| GET | `/v1/species/:id/sites` | Sites where species has been seen |

### Sightings

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/sightings` | List sightings (filters: site, species, user) |
| POST | `/v1/sightings` | Create sighting |
| PATCH | `/v1/sightings/:id/verify` | Expert verification |

### Dive logs

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/dive-logs` | User's dive logs |
| POST | `/v1/dive-logs` | Create dive log |
| PATCH | `/v1/dive-logs/:id` | Update dive log |

### Users

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/users/me` | Current user profile |
| PATCH | `/v1/users/me` | Update profile |
| GET | `/v1/users/me/stats` | Aggregate dive stats |
| GET | `/v1/users/me/life-list` | Species life list |
| GET | `/v1/users/me/badges` | Earned badges |

### Operators (B2B)

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/v1/operators` | Optional | List operators |
| GET | `/v1/operators/me` | Yes | Operator profile for current user |
| GET | `/v1/operators/me/dashboard/kpis` | Yes | Dashboard KPI cards |
| GET | `/v1/operators/me/dashboard/charts` | Yes | Sightings trend + dives by site |
| GET | `/v1/operators/me/dashboard/activity` | Yes | Recent activity feed |
| GET | `/v1/operators/me/analytics` | Yes | Heatmap, diversity, depth, retention |
| GET | `/v1/operators/me/customers` | Yes | Paginated customer directory |
| GET | `/v1/operators/me/species` | Yes | Paginated species rankings |
| GET | `/v1/operators/:slug` | Optional | Public operator profile |
| GET | `/v1/operators/:operatorId/members` | Yes | Team members |
| POST | `/v1/operators/:operatorId/members` | Yes (owner) | Invite user by `user_id` |
| GET | `/v1/operators/:operatorId/sites` | Yes | Linked dive sites |
| GET | `/v1/operators/:operatorId/analytics/kpis` | Yes | KPIs with window query |

## Supabase RPC functions

| Function | Parameters | Returns |
|----------|------------|---------|
| `nearby_dive_sites` | `p_lat`, `p_lng`, `p_radius_km` | Nearby sites with distance |
| `species_at_site` | `p_site_id` | Species seen at a site with stats |
| `sites_with_species` | `p_species_id` | Sites where species was seen |
| `user_dive_stats` | `p_user_id` | JSON aggregate stats |
| `operator_kpis` | `p_operator_id`, `p_window_days` | Operator KPI JSON |
| `operator_dives_by_month` | `p_operator_id` | Monthly dive counts |

## Edge Functions

### Darwin Core export

```
GET /functions/v1/darwin-core-export?from=2025-01-01&verified_only=true&format=json
```

Query parameters:

| Param | Default | Description |
|-------|---------|-------------|
| `from` | — | Start date (ISO 8601) |
| `to` | — | End date |
| `country_code` | — | Filter by ISO country |
| `verified_only` | `true` | Only expert-verified sightings |
| `format` | `json` | `json` or `csv` |

Returns `DarwinCoreExportBundle` from `@benthyo/types`.

### Weekly digest

```
POST /functions/v1/weekly-digest
{ "dry_run": true, "user_id": "optional-uuid" }
```

## Photo uploads

Photos are stored in Cloudflare R2. The API returns presigned PUT URLs:

```
POST /v1/uploads/presign
{ "content_type": "image/jpeg", "sighting_id": "uuid" }
```

Response:

```json
{
  "data": {
    "upload_url": "https://...",
    "public_url": "https://photos.benthyo.com/..."
  }
}
```

## Rate limits

The NestJS API applies throttling via `@nestjs/throttler`:

- 100 requests/minute per IP for public endpoints
- 300 requests/minute for authenticated users

ETL pipelines use internal rate limiters respecting upstream API quotas (GBIF: 250ms, OBIS: 300ms, WoRMS: 150ms, Overpass: 2s).
