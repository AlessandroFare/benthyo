import { useQuery } from "@tanstack/react-query";
import { useParams } from "react-router-dom";
import { api } from "@/lib/api-client";
import type { Operator } from "@/lib/types";

export function EmbedBookingPage() {
  const { slug } = useParams<{ slug: string }>();

  const { data, isLoading, error } = useQuery({
    queryKey: ["embed-operator", slug],
    queryFn: () => api.get<Operator>(`/operators/${slug}`),
    enabled: Boolean(slug),
  });

  if (isLoading) {
    return <p style={{ fontFamily: "system-ui", padding: 24 }}>Loading…</p>;
  }
  if (error || !data) {
    return <p style={{ fontFamily: "system-ui", padding: 24 }}>Operator not found</p>;
  }

  return (
    <div
      style={{
        fontFamily: "system-ui",
        padding: 24,
        maxWidth: 480,
        margin: "0 auto",
      }}
    >
      <h1 style={{ margin: 0 }}>{data.name}</h1>
      <p style={{ color: "#555" }}>
        {data.region
          ? `Dive with us in ${data.region}.`
          : "Book your next dive with us."}
      </p>
      <p style={{ color: "#555" }}>Powered by Benthyo</p>
      {data.website && (
        <a href={data.website} style={{ display: "inline-block", marginBottom: 16 }}>
          Visit website
        </a>
      )}
      <div
        style={{
          border: "1px solid #0d6b7a",
          borderRadius: 12,
          padding: 16,
          background: "#f0f9fa",
        }}
      >
        <strong>Ready to dive?</strong>
        <p style={{ margin: "8px 0 0", fontSize: 14 }}>
          Download Benthyo to log dives, sign the digital waiver, and explore our sites.
        </p>
      </div>
      <p style={{ fontSize: 12, color: "#888", marginTop: 24 }}>
        Embed:{" "}
        <code>{`<iframe src="${window.location.origin}/embed/${slug}/book" width="400" height="500" />`}</code>
      </p>
    </div>
  );
}
