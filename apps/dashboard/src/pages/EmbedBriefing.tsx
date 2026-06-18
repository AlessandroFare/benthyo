import { useQuery } from "@tanstack/react-query";
import { useParams } from "react-router-dom";
import { api } from "@/lib/api-client";

type Briefing = {
  operator: { name: string; slug: string; email: string | null; website: string | null };
  waiver: { title: string; excerpt: string } | null;
  links: { sign_waiver: string; medical_form: string };
};

export function EmbedBriefingPage() {
  const { slug } = useParams<{ slug: string }>();

  const { data, isLoading, error } = useQuery({
    queryKey: ["embed-briefing", slug],
    queryFn: () => api.get<Briefing>(`/public/operators/${slug}/briefing`),
    enabled: Boolean(slug),
  });

  if (isLoading) {
    return <p style={{ fontFamily: "system-ui", padding: 24 }}>Loading…</p>;
  }
  if (error || !data) {
    return <p style={{ fontFamily: "system-ui", padding: 24 }}>Operator not found</p>;
  }

  const base = window.location.origin.replace(/:\d+$/, ":5173");

  return (
    <div
      style={{
        fontFamily: "system-ui",
        padding: 24,
        maxWidth: 420,
        margin: "0 auto",
        border: "1px solid #0d6b7a",
        borderRadius: 12,
        background: "#fff",
      }}
    >
      <h1 style={{ margin: "0 0 8px", fontSize: 22 }}>{data.operator.name}</h1>
      <p style={{ margin: 0, color: "#555" }}>Pre-dive guest briefing</p>

      {data.waiver && (
        <div style={{ marginTop: 16, padding: 12, background: "#f5f5f5", borderRadius: 8 }}>
          <strong>{data.waiver.title}</strong>
          <p style={{ fontSize: 14, margin: "8px 0 0" }}>{data.waiver.excerpt}…</p>
        </div>
      )}

      <div style={{ display: "flex", flexDirection: "column", gap: 10, marginTop: 20 }}>
        <a
          href={`${base}${data.links.sign_waiver}`}
          style={{
            display: "block",
            textAlign: "center",
            padding: "12px 16px",
            background: "#0d6b7a",
            color: "#fff",
            borderRadius: 8,
            textDecoration: "none",
          }}
        >
          Sign liability waiver
        </a>
        <a
          href={`${base}${data.links.medical_form}`}
          style={{
            display: "block",
            textAlign: "center",
            padding: "12px 16px",
            border: "1px solid #0d6b7a",
            color: "#0d6b7a",
            borderRadius: 8,
            textDecoration: "none",
          }}
        >
          Complete medical form
        </a>
      </div>

      <p style={{ fontSize: 11, color: "#888", marginTop: 20 }}>Powered by OceanLog</p>
      <p style={{ fontSize: 11, color: "#888" }}>
        <code>{`<iframe src="${window.location.origin}/embed/briefing/${slug}" width="420" height="360" />`}</code>
      </p>
    </div>
  );
}
