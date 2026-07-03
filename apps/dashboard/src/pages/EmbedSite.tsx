import { useQuery } from "@tanstack/react-query";
import { useParams } from "react-router-dom";
import { api } from "@/lib/api-client";

type SiteCard = {
  name: string;
  slug: string;
  region: string | null;
  country_code: string;
  total_dives: number;
  total_species: number;
  verified_sightings: number;
  last_dive_at: string | null;
  avg_depth_m: number | null;
  avg_visibility_m: number | null;
};

export function EmbedSitePage() {
  const { slug } = useParams<{ slug: string }>();

  const { data, isLoading, error } = useQuery({
    queryKey: ["embed-site", slug],
    queryFn: () => api.get<SiteCard>(`/public/sites/${slug}/card`),
    enabled: Boolean(slug),
  });

  if (isLoading) {
    return <p style={{ fontFamily: "system-ui", padding: 24 }}>Loading…</p>;
  }
  if (error || !data) {
    return <p style={{ fontFamily: "system-ui", padding: 24 }}>Site not found</p>;
  }

  return (
    <div
      style={{
        fontFamily: "system-ui",
        padding: 20,
        maxWidth: 360,
        margin: "0 auto",
        border: "1px solid #0d6b7a",
        borderRadius: 12,
        background: "#f0f9fa",
      }}
    >
      <h2 style={{ margin: "0 0 4px" }}>{data.name}</h2>
      <p style={{ margin: 0, color: "#555", fontSize: 14 }}>
        {data.region ?? data.country_code}
      </p>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginTop: 16 }}>
        <Stat label="Dives logged" value={String(data.total_dives)} />
        <Stat label="Species" value={String(data.total_species)} />
        <Stat label="Verified" value={String(data.verified_sightings)} />
        <Stat
          label="Last dive"
          value={data.last_dive_at ? new Date(data.last_dive_at).toLocaleDateString() : "—"}
        />
      </div>
      {(data.avg_depth_m != null || data.avg_visibility_m != null) && (
        <p style={{ fontSize: 13, color: "#444", marginTop: 12 }}>
          {data.avg_depth_m != null && `Avg depth ${data.avg_depth_m} m`}
          {data.avg_depth_m != null && data.avg_visibility_m != null && " · "}
          {data.avg_visibility_m != null && `Avg vis ${data.avg_visibility_m} m`}
        </p>
      )}
      <p style={{ fontSize: 11, color: "#888", marginTop: 16 }}>Powered by Benthyo</p>
      <p style={{ fontSize: 11, color: "#888" }}>
        <code>{`<iframe src="${window.location.origin}/embed/site/${slug}" width="360" height="280" />`}</code>
      </p>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div style={{ fontSize: 22, fontWeight: 700, color: "#0d6b7a" }}>{value}</div>
      <div style={{ fontSize: 12, color: "#666" }}>{label}</div>
    </div>
  );
}

export function EmbedPrepPage() {
  const { slug } = useParams<{ slug: string }>();

  const { data, isLoading, error } = useQuery({
    queryKey: ["embed-prep", slug],
    queryFn: () =>
      api.get<{
        site: SiteCard;
        recent_reviews: Array<{ body: string; rating: number; username: string }>;
        recent_species: Array<{ common_name: string; scientific_name: string }>;
      }>(`/public/sites/${slug}/prep-card`),
    enabled: Boolean(slug),
  });

  if (isLoading) {
    return <p style={{ fontFamily: "system-ui", padding: 24 }}>Loading…</p>;
  }
  if (error || !data) {
    return <p style={{ fontFamily: "system-ui", padding: 24 }}>Prep card not found</p>;
  }

  const site = data.site;

  return (
    <div style={{ fontFamily: "system-ui", padding: 24, maxWidth: 520, margin: "0 auto" }}>
      <h1 style={{ margin: 0 }}>Pre-dive: {site.name}</h1>
      <p style={{ color: "#555" }}>
        {site.total_dives} dives logged · {site.total_species} species · share with your boat group
      </p>
      {data.recent_reviews?.length > 0 && (
        <>
          <h3>Recent diver reviews</h3>
          {data.recent_reviews.slice(0, 5).map((r, i) => (
            <blockquote key={i} style={{ margin: "8px 0", paddingLeft: 12, borderLeft: "3px solid #0d6b7a" }}>
              {r.body ?? "No notes"} — @{r.username} ({r.rating}/5)
            </blockquote>
          ))}
        </>
      )}
      {data.recent_species?.length > 0 && (
        <>
          <h3>Spotted recently</h3>
          <p>{data.recent_species.map((s) => s.common_name ?? s.scientific_name).join(", ")}</p>
        </>
      )}
      <p style={{ fontSize: 12, color: "#888" }}>Powered by Benthyo</p>
    </div>
  );
}
