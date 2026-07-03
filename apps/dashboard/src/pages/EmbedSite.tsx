import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useParams } from "react-router-dom";
import { api } from "@/lib/api-client";

// ─── Types ────────────────────────────────────────────────────────────────────

type SiteCard = {
  site_id: string;
  name: string;
  slug: string;
  region: string | null;
  country_code: string;
  difficulty: string | null;
  depth_max: number | null;
  total_dives: number;
  total_species: number;
  verified_sightings: number;
  last_dive_at: string | null;
  avg_depth_m: number | null;
  avg_visibility_m: number | null;
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

function fmt(n: number | null | undefined): string {
  if (n == null) return "—";
  return n.toLocaleString();
}

function fmtDate(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

function difficultyLabel(d: string | null): string | null {
  if (!d) return null;
  const map: Record<string, string> = {
    beginner: "Beginner",
    intermediate: "Intermediate",
    advanced: "Advanced",
    technical: "Technical",
  };
  return map[d.toLowerCase()] ?? d;
}

// ─── Shared card shell (used both in the standalone widget and the prep card) ─

function SiteCardShell({
  data,
  showSnippet = false,
  embedUrl,
}: {
  data: SiteCard;
  showSnippet?: boolean;
  embedUrl?: string;
}) {
  const [copied, setCopied] = useState(false);

  const snippet = embedUrl
    ? `<iframe\n  src="${embedUrl}"\n  width="380"\n  height="260"\n  frameborder="0"\n  style="border-radius:14px;border:none;"\n  title="${data.name} — Benthyo dive site"\n></iframe>`
    : null;

  function copySnippet() {
    if (!snippet) return;
    navigator.clipboard.writeText(snippet).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  }

  const difficulty = difficultyLabel(data.difficulty);

  return (
    <div
      style={{
        fontFamily:
          "'Inter', system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
        background: "linear-gradient(135deg, #0c4a6e 0%, #0e7490 55%, #0891b2 100%)",
        borderRadius: 14,
        padding: "20px 22px 18px",
        maxWidth: 380,
        boxSizing: "border-box",
        color: "#fff",
        position: "relative",
        overflow: "hidden",
      }}
    >
      {/* Subtle background wave */}
      <div
        aria-hidden
        style={{
          position: "absolute",
          inset: 0,
          backgroundImage:
            "radial-gradient(ellipse at 80% 110%, rgba(14,165,233,0.25) 0%, transparent 65%)",
          pointerEvents: "none",
        }}
      />

      {/* Header */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 12 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <p
            style={{
              margin: "0 0 2px",
              fontSize: 11,
              fontWeight: 600,
              letterSpacing: "0.08em",
              textTransform: "uppercase",
              color: "rgba(186,230,253,0.8)",
            }}
          >
            Dive site
          </p>
          <h2
            style={{
              margin: "0 0 3px",
              fontSize: 20,
              fontWeight: 800,
              lineHeight: 1.15,
              letterSpacing: "-0.01em",
              color: "#fff",
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "ellipsis",
            }}
          >
            {data.name}
          </h2>
          <p style={{ margin: 0, fontSize: 12, color: "rgba(186,230,253,0.75)", fontWeight: 500 }}>
            {[data.region, data.country_code].filter(Boolean).join(", ")}
          </p>
        </div>

        {/* Benthyo mark */}
        <div
          style={{
            flexShrink: 0,
            width: 36,
            height: 36,
            borderRadius: "50%",
            background: "rgba(255,255,255,0.12)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 18,
          }}
          aria-hidden
        >
          🐙
        </div>
      </div>

      {/* Badges row */}
      {(difficulty || data.depth_max != null) && (
        <div style={{ display: "flex", gap: 6, marginTop: 10, flexWrap: "wrap" }}>
          {difficulty && (
            <span
              style={{
                background: "rgba(255,255,255,0.15)",
                borderRadius: 100,
                padding: "2px 10px",
                fontSize: 11,
                fontWeight: 600,
                color: "#e0f2fe",
              }}
            >
              {difficulty}
            </span>
          )}
          {data.depth_max != null && (
            <span
              style={{
                background: "rgba(255,255,255,0.15)",
                borderRadius: 100,
                padding: "2px 10px",
                fontSize: 11,
                fontWeight: 600,
                color: "#e0f2fe",
              }}
            >
              Max {data.depth_max} m
            </span>
          )}
        </div>
      )}

      {/* Stats grid */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "1fr 1fr 1fr",
          gap: "10px 8px",
          marginTop: 16,
        }}
      >
        <StatCell label="Dives logged" value={fmt(data.total_dives)} />
        <StatCell label="Species" value={fmt(data.total_species)} />
        <StatCell label="Verified" value={fmt(data.verified_sightings)} />
        {data.avg_depth_m != null && (
          <StatCell label="Avg depth" value={`${data.avg_depth_m} m`} />
        )}
        {data.avg_visibility_m != null && (
          <StatCell label="Avg vis." value={`${data.avg_visibility_m} m`} />
        )}
        {data.last_dive_at && (
          <StatCell label="Last dive" value={fmtDate(data.last_dive_at)} small />
        )}
      </div>

      {/* Footer */}
      <div
        style={{
          marginTop: 14,
          paddingTop: 10,
          borderTop: "1px solid rgba(255,255,255,0.12)",
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
        }}
      >
        <span style={{ fontSize: 11, color: "rgba(186,230,253,0.6)", fontWeight: 500 }}>
          Powered by{" "}
          <strong style={{ color: "rgba(186,230,253,0.9)" }}>Benthyo</strong>
        </span>
        {data.slug && (
          <a
            href={`https://benthyo.com/sites/${data.slug}`}
            target="_blank"
            rel="noopener noreferrer"
            style={{
              fontSize: 11,
              color: "#7dd3fc",
              textDecoration: "none",
              fontWeight: 600,
            }}
          >
            View full site &rarr;
          </a>
        )}
      </div>

      {/* Embed snippet (only in the generator view, not the iframe) */}
      {showSnippet && snippet && (
        <div style={{ marginTop: 16 }}>
          <p style={{ margin: "0 0 6px", fontSize: 11, color: "rgba(186,230,253,0.7)", fontWeight: 600 }}>
            Embed on your website
          </p>
          <div
            style={{
              background: "rgba(0,0,0,0.35)",
              borderRadius: 8,
              padding: "10px 12px",
              position: "relative",
            }}
          >
            <pre
              style={{
                margin: 0,
                fontSize: 10.5,
                color: "#bae6fd",
                whiteSpace: "pre-wrap",
                wordBreak: "break-all",
                lineHeight: 1.55,
                fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
              }}
            >
              {snippet}
            </pre>
            <button
              onClick={copySnippet}
              style={{
                position: "absolute",
                top: 8,
                right: 8,
                background: copied ? "rgba(34,197,94,0.3)" : "rgba(255,255,255,0.15)",
                border: "none",
                borderRadius: 6,
                padding: "4px 10px",
                cursor: "pointer",
                color: copied ? "#86efac" : "#e0f2fe",
                fontSize: 11,
                fontWeight: 600,
                transition: "background 0.2s, color 0.2s",
              }}
            >
              {copied ? "Copied!" : "Copy"}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

function StatCell({
  label,
  value,
  small = false,
}: {
  label: string;
  value: string;
  small?: boolean;
}) {
  return (
    <div>
      <div
        style={{
          fontSize: small ? 14 : 20,
          fontWeight: 800,
          color: "#fff",
          lineHeight: 1.1,
          letterSpacing: small ? 0 : "-0.01em",
        }}
      >
        {value}
      </div>
      <div style={{ fontSize: 10.5, color: "rgba(186,230,253,0.65)", marginTop: 2, fontWeight: 500 }}>
        {label}
      </div>
    </div>
  );
}

// ─── Loading / Error shells ───────────────────────────────────────────────────

function LoadingShell() {
  return (
    <div
      style={{
        fontFamily: "system-ui",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        minHeight: 140,
        color: "#64748b",
        fontSize: 14,
      }}
    >
      Loading site data…
    </div>
  );
}

function ErrorShell({ message }: { message: string }) {
  return (
    <div
      style={{
        fontFamily: "system-ui",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        minHeight: 140,
        color: "#ef4444",
        fontSize: 14,
      }}
    >
      {message}
    </div>
  );
}

// ─── Public embed widget (/embed/site/:slug) ──────────────────────────────────

export function EmbedSitePage() {
  const { slug } = useParams<{ slug: string }>();

  const { data, isLoading, error } = useQuery({
    queryKey: ["embed-site", slug],
    queryFn: () => api.get<SiteCard>(`/public/sites/${slug}/card`),
    enabled: Boolean(slug),
    staleTime: 5 * 60_000,
  });

  if (isLoading) return <LoadingShell />;
  if (error || !data) return <ErrorShell message="Site not found." />;

  return (
    <div style={{ padding: 8 }}>
      <SiteCardShell data={data} />
    </div>
  );
}

// ─── Generator / preview page (/embed/site/:slug?preview=1) ──────────────────
// Also served as the operator-facing "get embed code" page from the dashboard.

export function EmbedSiteGeneratorPage() {
  const { slug } = useParams<{ slug: string }>();

  const { data, isLoading, error } = useQuery({
    queryKey: ["embed-site", slug],
    queryFn: () => api.get<SiteCard>(`/public/sites/${slug}/card`),
    enabled: Boolean(slug),
    staleTime: 5 * 60_000,
  });

  const embedUrl = `${window.location.origin}/embed/site/${slug}`;

  return (
    <div
      style={{
        fontFamily: "system-ui",
        minHeight: "100vh",
        background: "#f8fafc",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: 24,
        gap: 24,
      }}
    >
      <div style={{ textAlign: "center", maxWidth: 440 }}>
        <h1 style={{ margin: "0 0 6px", fontSize: 22, fontWeight: 800, color: "#0c4a6e" }}>
          Dive site embed
        </h1>
        <p style={{ margin: 0, fontSize: 14, color: "#64748b" }}>
          Copy the code below to embed live dive stats on any website.
        </p>
      </div>

      {isLoading && <LoadingShell />}
      {(error || (!isLoading && !data)) && <ErrorShell message="Site not found." />}
      {data && (
        <SiteCardShell data={data} showSnippet embedUrl={embedUrl} />
      )}
    </div>
  );
}

// ─── Prep card (/embed/site/:slug/prep) ──────────────────────────────────────

type PrepCard = {
  site: SiteCard;
  recent_reviews: Array<{ body: string; rating: number; username: string }>;
  recent_species: Array<{ common_name: string | null; scientific_name: string }>;
};

export function EmbedPrepPage() {
  const { slug } = useParams<{ slug: string }>();

  const { data, isLoading, error } = useQuery({
    queryKey: ["embed-prep", slug],
    queryFn: () => api.get<PrepCard>(`/public/sites/${slug}/prep-card`),
    enabled: Boolean(slug),
    staleTime: 5 * 60_000,
  });

  if (isLoading) return <LoadingShell />;
  if (error || !data) return <ErrorShell message="Prep card not found." />;

  const site = data.site;

  return (
    <div
      style={{
        fontFamily:
          "'Inter', system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
        maxWidth: 520,
        margin: "0 auto",
        padding: 24,
        color: "#0f172a",
      }}
    >
      {/* Site summary card */}
      <SiteCardShell data={site} />

      {/* Reviews */}
      {data.recent_reviews?.length > 0 && (
        <section style={{ marginTop: 24 }}>
          <h3
            style={{
              margin: "0 0 10px",
              fontSize: 14,
              fontWeight: 700,
              color: "#0c4a6e",
              textTransform: "uppercase",
              letterSpacing: "0.06em",
            }}
          >
            Recent diver reviews
          </h3>
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            {data.recent_reviews.slice(0, 5).map((r, i) => (
              <div
                key={i}
                style={{
                  background: "#f0f9ff",
                  borderLeft: "3px solid #0ea5e9",
                  borderRadius: "0 8px 8px 0",
                  padding: "10px 14px",
                }}
              >
                <p style={{ margin: "0 0 4px", fontSize: 13, lineHeight: 1.55, color: "#1e293b" }}>
                  {r.body ?? "No notes left."}
                </p>
                <p style={{ margin: 0, fontSize: 11, color: "#64748b" }}>
                  @{r.username} &middot; {r.rating}/5
                </p>
              </div>
            ))}
          </div>
        </section>
      )}

      {/* Recently spotted species */}
      {data.recent_species?.length > 0 && (
        <section style={{ marginTop: 20 }}>
          <h3
            style={{
              margin: "0 0 8px",
              fontSize: 14,
              fontWeight: 700,
              color: "#0c4a6e",
              textTransform: "uppercase",
              letterSpacing: "0.06em",
            }}
          >
            Spotted recently
          </h3>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
            {data.recent_species.map((s, i) => (
              <span
                key={i}
                style={{
                  background: "#e0f2fe",
                  color: "#0369a1",
                  borderRadius: 100,
                  padding: "4px 12px",
                  fontSize: 12,
                  fontWeight: 600,
                }}
              >
                {s.common_name ?? s.scientific_name}
              </span>
            ))}
          </div>
        </section>
      )}

      <p style={{ marginTop: 24, fontSize: 11, color: "#94a3b8" }}>
        Powered by <strong style={{ color: "#0369a1" }}>Benthyo</strong>
      </p>
    </div>
  );
}
