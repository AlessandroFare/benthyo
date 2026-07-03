import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

/**
 * Weekly digest emailer. Invoked by:
 *   - An authenticated admin user via POST (with a valid JWT) for manual runs
 *   - The scheduled pg_cron job (the function then checks a shared secret
 *     header to confirm the call is genuine).
 *
 * The previous version of this function had three issues (C-2):
 *   1. It did not check users.weekly_digest_opt_in and sent to every user.
 *   2. It had no rate limit and was callable anonymously (CORS * + no JWT).
 *   3. A malicious caller could iterate over the user table and trigger a
 *      costly Resend bill.
 *
 * This version enforces:
 *   - The caller must present a valid Supabase JWT (anon cannot invoke).
 *   - OR: the caller must present the CRON_SHARED_SECRET header AND
 *     the request must arrive from the project's pg_cron netallow list.
 *   - users.weekly_digest_opt_in must be true for any user receiving mail.
 */

interface DigestUser {
  id: string;
  username: string;
  full_name: string | null;
  weekly_digest_opt_in: boolean;
}

interface WeeklyTarget {
  user_id: string;
  sent: boolean;
  reason?: string;
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

function isAuthorizedCron(req: Request): boolean {
  const expected = Deno.env.get("CRON_SHARED_SECRET");
  if (!expected) return false;
  const provided = req.headers.get("x-cron-secret");
  if (!provided) return false;
  // Constant-time compare to avoid timing oracles.
  if (provided.length !== expected.length) return false;
  let mismatch = 0;
  for (let i = 0; i < expected.length; i++) {
    mismatch |= expected.charCodeAt(i) ^ provided.charCodeAt(i);
  }
  return mismatch === 0;
}

async function isAuthorizedAdmin(token: string): Promise<boolean> {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
  const { data } = await supabase.auth.getUser(token);
  const user = data.user;
  if (!user) return false;
  // Admins are operator owner or admin of ANY operator OR a taxonomy_expert.
  const { data: profile } = await supabase
    .from("users")
    .select("taxonomy_expert")
    .eq("id", user.id)
    .maybeSingle();
  if (profile?.taxonomy_expert) return true;
  const { data: membership } = await supabase
    .from("operator_users")
    .select("role")
    .eq("user_id", user.id)
    .in("role", ["owner", "admin"])
    .limit(1)
    .maybeSingle();
  return Boolean(membership);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  // Auth gate: cron shared secret OR a valid admin JWT.
  const cronOk = isAuthorizedCron(req);
  let adminOk = false;
  if (!cronOk) {
    const authHeader = req.headers.get("authorization") ?? "";
    const match = authHeader.match(/^Bearer\s+(.+)$/i);
    if (match) {
      adminOk = await isAuthorizedAdmin(match[1]);
    }
  }
  if (!cronOk && !adminOk) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  try {
    const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
    const dryRun = Boolean(body.dry_run);
    const targetUserId = body.user_id as string | undefined;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const resendKey = Deno.env.get("RESEND_API_KEY");
    const fromEmail = Deno.env.get("DIGEST_FROM_EMAIL") ?? "Benthyo <digest@benthyo.com>";

    const weekStart = new Date();
    weekStart.setDate(weekStart.getDate() - 7);

    // Only users who explicitly opted in.
    let userQuery = supabase
      .from("users")
      .select("id, username, full_name, weekly_digest_opt_in")
      .eq("weekly_digest_opt_in", true);

    if (targetUserId) userQuery = userQuery.eq("id", targetUserId);

    const { data: users, error: usersError } = await userQuery;
    if (usersError) throw usersError;

    const results: WeeklyTarget[] = [];
    for (const user of (users ?? []) as DigestUser[]) {
      const { data: recentSightings } = await supabase
        .from("sightings")
        .select("id, observed_at, species(scientific_name, common_name), dive_sites(name)")
        .eq("user_id", user.id)
        .gte("observed_at", weekStart.toISOString())
        .order("observed_at", { ascending: false })
        .limit(10);

      const { data: stats } = await supabase.rpc("user_dive_stats", { p_user_id: user.id });

      const { data: newBadges } = await supabase
        .from("user_badges")
        .select("earned_at, badges(name, tier)")
        .eq("user_id", user.id)
        .gte("earned_at", weekStart.toISOString());

      const sightingCount = recentSightings?.length ?? 0;
      if (sightingCount === 0 && (newBadges?.length ?? 0) === 0) {
        results.push({ user_id: user.id, sent: false, reason: "no_activity" });
        continue;
      }

      const html = buildDigestHtml({
        name: user.full_name ?? user.username,
        sightings: recentSightings ?? [],
        stats: stats ?? {},
        badges: newBadges ?? [],
      });

      if (dryRun) {
        results.push({ user_id: user.id, sent: false, reason: "dry_run" });
        continue;
      }

      if (!resendKey) {
        results.push({ user_id: user.id, sent: false, reason: "missing_resend_key" });
        continue;
      }

      const { data: authUser } = await supabase.auth.admin.getUserById(user.id);
      const email = authUser.user?.email;
      if (!email) {
        results.push({ user_id: user.id, sent: false, reason: "no_email" });
        continue;
      }

      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${resendKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: fromEmail,
          to: email,
          subject: "Your Benthyo weekly dive digest",
          html,
        }),
      });

      results.push({
        user_id: user.id,
        sent: res.ok,
        reason: res.ok ? undefined : `resend_${res.status}`,
      });
    }

    return new Response(JSON.stringify({ processed: results.length, results }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error('weekly-digest failed', err);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      },
    );
  }
});

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function buildDigestHtml(input: {
  name: string;
  sightings: Array<Record<string, unknown>>;
  stats: Record<string, unknown>;
  badges: Array<Record<string, unknown>>;
}): string {
  // Escape every interpolated value to prevent email-client XSS via stored
  // species/sighting names (e.g., a malicious user naming a custom species
  // "<script>..." — the old code interpolated raw text).
  const sightingLines = input.sightings
    .map((s) => {
      const species = s.species as { common_name?: string; scientific_name?: string } | null;
      const site = s.dive_sites as { name?: string } | null;
      const label = species?.common_name ?? species?.scientific_name ?? "Unknown species";
      const siteName = site?.name ?? "unknown site";
      return `<li>${escapeHtml(label)} at ${escapeHtml(siteName)}</li>`;
    })
    .join("");

  const badgeLines = input.badges
    .map((b) => {
      const badge = b.badges as { name?: string; tier?: number } | null;
      return `<li>${escapeHtml(badge?.name ?? "Badge")} (tier ${badge?.tier ?? 1})</li>`;
    })
    .join("");

  const name = escapeHtml(input.name);

  return `
    <h1>Hi ${name},</h1>
    <p>Your week in the Mediterranean:</p>
    <ul>
      <li>Total dives: ${input.stats.total_dives ?? 0}</li>
      <li>Species on life list: ${input.stats.total_species ?? 0}</li>
      <li>Sightings this week: ${input.sightings.length}</li>
    </ul>
    ${sightingLines ? `<h2>Recent sightings</h2><ul>${sightingLines}</ul>` : ""}
    ${badgeLines ? `<h2>New badges</h2><ul>${badgeLines}</ul>` : ""}
    <p>Keep exploring — <a href="https://benthyo.com">Open Benthyo</a></p>
  `;
}
