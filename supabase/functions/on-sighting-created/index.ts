import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface BadgeRow {
  id: string;
  code: string;
  name: string;
  criteria_type: string;
  criteria_value: Record<string, unknown>;
  tier: number;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = await req.json();
    const sighting = payload.record ?? payload;

    if (!sighting?.user_id) {
      return new Response(JSON.stringify({ error: "Missing user_id in payload" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const userId = sighting.user_id as string;
    const awarded: BadgeRow[] = [];

    const { data: badges } = await supabase.from("badges").select("*");
    if (!badges?.length) {
      return new Response(JSON.stringify({ awarded: [] }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: existingBadges } = await supabase
      .from("user_badges")
      .select("badge_id")
      .eq("user_id", userId);

    const earnedIds = new Set((existingBadges ?? []).map((b) => b.badge_id));

    const { data: userStats } = await supabase.rpc("user_dive_stats", {
      p_user_id: userId,
    });

    for (const badge of badges as BadgeRow[]) {
      if (earnedIds.has(badge.id)) continue;

      const criteria = badge.criteria_value ?? {};
      let qualifies = false;
      const context: Record<string, unknown> = {};

      switch (badge.criteria_type) {
        case "dive_count": {
          const threshold = Number(criteria.count ?? 0);
          qualifies = (userStats?.total_dives ?? 0) >= threshold;
          context.total_dives = userStats?.total_dives;
          break;
        }
        case "species_count": {
          const threshold = Number(criteria.count ?? 0);
          qualifies = (userStats?.total_species ?? 0) >= threshold;
          context.total_species = userStats?.total_species;
          break;
        }
        case "site_count": {
          const threshold = Number(criteria.count ?? 0);
          qualifies = (userStats?.total_sites ?? 0) >= threshold;
          context.total_sites = userStats?.total_sites;
          break;
        }
        case "region": {
          const regions = (criteria.regions ?? []) as string[];
          if (regions.includes("mediterranean")) {
            const { count } = await supabase
              .from("dive_logs")
              .select("id", { count: "exact", head: true })
              .eq("user_id", userId)
              .not("dive_site_id", "is", null);
            qualifies = (count ?? 0) > 0;
          }
          break;
        }
        default:
          break;
      }

      if (!qualifies) continue;

      const { error } = await supabase.from("user_badges").upsert(
        {
          user_id: userId,
          badge_id: badge.id,
          context_json: context,
        },
        { onConflict: "user_id,badge_id", ignoreDuplicates: true },
      );

      if (!error) awarded.push(badge);
    }

    return new Response(JSON.stringify({ awarded }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : String(err) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
