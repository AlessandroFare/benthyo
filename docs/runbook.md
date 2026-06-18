# OceanLog — On-call Runbook

This is the playbook for the on-call engineer. It is intentionally
short. If you find yourself doing something not in this runbook,
update this file when you're done.

## 0. On-call quick reference

| Symptom | First thing to check | Runbook entry |
|---|---|---|
| Dashboard 5xx | `/health/ready` on the API | §1 |
| API 5xx | `railway logs --follow` | §1 |
| Mobile shows "0 sightings" | DB connectivity / RLS | §2 |
| Sentry alert: "GDPR export failed" | Function deploys / env | §3 |
| Stripe webhook not firing | `stripe events list` | §4 |
| Dead-letter queue is growing | `pnpm --filter @oceanlog/etl sync-queue-inspect` | §5 |
| RLS test suite red | `psql $DATABASE_URL -f supabase/tests/rls.sql` | §6 |
| pgcron job missing | `SELECT * FROM cron.job;` | §7 |
| MEDICAL_ENCRYPTION_MASTER_KEY rotation | manual SQL + deploy | §8 |
| GDPR erasure request | `auth.admin.deleteUser` | §9 |

## 1. API 5xx

```bash
# 1.1 Liveness / readiness probes
curl https://api.oceanlog.app/health/live
curl https://api.oceanlog.app/health/ready

# 1.2 If the readiness probe fails, check:
#     - Supabase URL reachable?
#     - SUPABASE_SERVICE_ROLE_KEY still valid?
#     - R2 credentials still valid? (test a presigned PUT)
#     - Stripe key expired?

# 1.3 Tail logs.
railway logs --follow --service api
#    Common signatures:
#      "Supabase URL/keys are not configured for production"
#        -> One of the env vars was unset during a deploy. Roll back.
#      "PGRST116"
#        -> A query returned 0 rows. Probably a missing
#           left-join. Check the recent commits.
#      "JWT expired"
#        -> The user's session expired. Client should refresh.
#           If you see this server-side, your guard is reading
#           the token without auto-refresh.
```

## 2. RLS regression

```bash
# 2.1 Run the RLS test suite. This file ships with the repo and
#     must be re-run on every schema change.
psql $DATABASE_URL -v ON_ERROR_STOP=1 -f supabase/tests/rls.sql
#    Expected output: "All OceanLog RLS tests passed."

# 2.2 If a test fails, read the failing policy. The most common
#     regression is a DROP POLICY that wasn't replaced.

# 2.3 To inspect the policies on a specific table:
psql $DATABASE_URL -c "\d+ <table_name>"
```

## 3. GDPR export failures

```bash
# 3.1 The /v1/users/me/export route calls export_user_data RPC.
#     A failure usually means the user has no profile row yet
#     (e.g. they signed up via OAuth but never finished onboarding).

# 3.2 To verify the RPC works on a specific user:
psql $DATABASE_URL -c "SELECT export_user_data('00000000-0000-0000-0000-000000000000'::UUID);"

# 3.3 If the RPC doesn't exist, re-apply migration 026.
```

## 4. Stripe webhook not firing

```bash
# 4.1 List recent events
stripe events list --limit 20

# 4.2 Replay a single event
stripe events resend evt_xxx

# 4.3 If signatures are failing, regenerate the webhook secret:
stripe webhooks endpoints update we_xxx --new-webhook-secret
#    Copy the new value to STRIPE_WEBHOOK_SECRET in Railway and
#    redeploy. Stripe uses a 5-minute tolerance; if you rotate
#    during a deploy the in-flight events will 401.
```

## 5. Dead-letter queue growing

```bash
# 5.1 The /v1/sync/dead-letter endpoint is the source of truth.
#     A growing queue usually means the user is offline or the
#     API is rejecting their writes. Common reasons:
#       - The user's role was downgraded and a write requires
#         a higher tier.
#       - The user's JWT expired and refresh isn't working on
#         the mobile client.
#       - A schema change made an old payload invalid.

# 5.2 To inspect a row from the dashboard:
#     SELECT id, endpoint, error, attempts, last_failed_at
#     FROM dead_letter
#     WHERE user_id = '...'
#     ORDER BY last_failed_at DESC
#     LIMIT 20;

# 5.3 To force-retry every row for a user, hit
#     POST /v1/sync/dead-letter/retry-all on their behalf.
```

## 6. pg_cron job missing

```bash
# 6.1 List scheduled jobs.
psql $DATABASE_URL -c "SELECT * FROM cron.job ORDER BY jobname;"

# 6.2 Expected jobs:
#     pgvector-reindex-monthly
#     prune-inat-identify-cache-weekly
#     reconcile-unmatched-nightly

# 6.3 If a job is missing, re-run the pg_cron block from
#     migration 034. The block is idempotent (checks
#     cron.job first).
```

## 7. Stripe / Supabase credential rotation

```bash
# 7.1 Stripe secret
stripe webhooks endpoints update we_xxx --new-webhook-secret
# Then update STRIPE_WEBHOOK_SECRET in Railway.

# 7.2 Supabase service role key
#    1. Generate a new key from the Supabase dashboard.
#    2. Update SUPABASE_SERVICE_ROLE_KEY in Railway.
#    3. Redeploy the API. The API will re-pickup on next start.

# 7.3 R2 access key
#    1. Generate a new key from the Cloudflare dashboard.
#    2. Update R2_ACCESS_KEY_ID + R2_SECRET_ACCESS_KEY in Railway.
#    3. Redeploy.
```

## 8. Medical encryption key derivation & rotation

### 8.0 GUC bootstrap quick-reference

| GUC | Env var | Purpose |
|-----|---------|---------|
| `app.medical_master_key` | `MEDICAL_ENCRYPTION_MASTER_KEY` | HMAC key for derivation |
| `app.medical_key_salt` | `MEDICAL_ENCRYPTION_KEY_SALT` | secret salt mixed into every key |

The key-derivation functions are `STABLE` (migration 040) because they read
these GUCs; never re-mark them `IMMUTABLE` (the planner could cache a stale
key across the rotation in §8.3).

Medical form answers (GDPR Article 9 "special category" data) are stored
as pgcrypto `pgp_sym_encrypt` ciphertext in `medical_form_submissions.answers`.
The passphrase is derived per scope (per-operator, or per-user for global
template submissions) by migration 038:

```
key = HMAC_SHA256(key = app.medical_master_key,
                  msg = scope || ':' || id || ':' || app.medical_key_salt)
```

Two runtime GUCs MUST be set (by the API process on boot, sourced from the
secret store):

- `app.medical_master_key` — the master key (env `MEDICAL_ENCRYPTION_MASTER_KEY`).
- `app.medical_key_salt`  — a secret salt mixed into every derivation.

The `answers_key_version` column records which derivation produced each row
(`1` = legacy md5, migration 030; `2` = HMAC-SHA256, migration 038). New
writes default to `2`.

> **Important:** never run a key-changing migration with the dev placeholder
> values. If `app.medical_master_key` is unset, migration 038's backfill
> skips with a NOTICE rather than corrupting data.

### 8.1 Provisioning (one-time, before first prod medical submission)

```sql
-- Set the GUCs at the database level so every session inherits them.
-- Values come from your secret store, NOT from this file.
ALTER DATABASE postgres SET app.medical_master_key = '<master-key>';
ALTER DATABASE postgres SET app.medical_key_salt   = '<secret-salt>';
-- Reconnect, then verify they are visible:
SELECT current_setting('app.medical_master_key', true) IS NOT NULL AS master_set,
       current_setting('app.medical_key_salt', true)   IS NOT NULL AS salt_set;
```

### 8.2 Backfilling legacy (v1) rows to v2

If the database already has rows written under the md5 scheme
(`answers_key_version = 1` or NULL), re-run migration 038's backfill with
the master key available. It is idempotent (a second run is a no-op):

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
  -f supabase/migrations/038_strengthen_medical_key_derivation.sql
```

Verify:

```sql
SELECT answers_key_version, count(*)
FROM medical_form_submissions
WHERE answers IS NOT NULL
GROUP BY 1;   -- expect all rows at version 2
```

### 8.3 Rotating the master key (or salt)

Rotation re-encrypts every row from the OLD derivation to the NEW one.
Run inside a transaction, with BOTH the old and new secrets available:

```sql
BEGIN;
-- 1. Inject the OLD secrets as locals so the old key can decrypt.
SET LOCAL app.medical_master_key = '<OLD-master-key>';
SET LOCAL app.medical_key_salt   = '<OLD-salt>';

-- 2. Decrypt every row into a TEMP table (visible only to this session).
CREATE TEMP TABLE _mfs_plain ON COMMIT DROP AS
SELECT id, user_id, operator_id,
       CASE WHEN operator_id IS NOT NULL
            THEN decrypt_medical_answers(operator_id, answers)
            ELSE decrypt_medical_answers_user(user_id, answers)
       END AS plain
FROM medical_form_submissions
WHERE answers IS NOT NULL;

-- 3. Swap to the NEW secrets and re-encrypt.
SET LOCAL app.medical_master_key = '<NEW-master-key>';
SET LOCAL app.medical_key_salt   = '<NEW-salt>';

UPDATE medical_form_submissions m
SET answers = CASE WHEN m.operator_id IS NOT NULL
                   THEN encrypt_medical_answers(m.operator_id, p.plain)
                   ELSE encrypt_medical_answers_user(m.user_id, p.plain)
              END,
    answers_key_version = 2
FROM _mfs_plain p
WHERE p.id = m.id;

COMMIT;
```

4. Update `app.medical_master_key` / `app.medical_key_salt` at the database
   level (§8.1) and in the API secret store, then redeploy the API.
5. Confirm decryption round-trips via `GET /v1/users/me/export` for a test
   account before announcing completion.

## 9. GDPR erasure request

The user has a right to be forgotten under GDPR Article 17. The
endpoint is `DELETE /v1/users/me` (the mobile app's Settings screen
exposes this). The endpoint:

1. Soft-deletes the user via the `soft_delete_row` RPC.
2. Lists + deletes R2 objects under `sightings/<userId>/` and
   `avatars/<userId>/`.
3. Calls `auth.admin.deleteUser(userId)`, which cascades the
   `public.users` row and every FK reference.

If the user reports that the deletion was incomplete:

```sql
-- 9.1 Verify the auth.users row is gone.
SELECT * FROM auth.users WHERE id = '<userId>';
--    Should return zero rows.

-- 9.2 If sightings still exist (the FK was set to NULL on
--     delete, but we use CASCADE for dive_logs / sightings):
SELECT COUNT(*) FROM sightings WHERE user_id = '<userId>';
--    Should be zero.

-- 9.3 If R2 objects remain, list and delete them:
SELECT key FROM storage.objects WHERE name LIKE 'sightings/<userId>/%';
--    The /v1/users/me endpoint already does this; the
--    R2 service is in apps/api/src/storage/r2.service.ts.
```

## 10. Responding to a "My data is wrong" request

The user can hit `GET /v1/users/me/export` to receive a JSON dump
of everything we store. The endpoint returns:

```json
{
  "meta": { "exported_at": "2026-...", "gdpr_article": "15" },
  "data": {
    "profile": {...},
    "dive_logs": [...],
    "sightings": [...],
    "user_life_list": [...],
    "user_badges": [...],
    "waiver_signatures": [...]
  }
}
```

The user can challenge any of these. The most common ones are
"my total_dives is wrong" and "I never signed that waiver".
Both are fixable by hand:

```sql
-- 10.1 Recompute total_dives
SELECT set_user_total_dives('<userId>');

-- 10.2 Soft-delete a waiver (the user can later ask for full
--     erasure, but soft-delete is reversible within 30 days)
SELECT soft_delete_row('waiver_signatures', '<waiverId>',
  'user_challenged_authenticity');
```
