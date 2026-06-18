import { useExpertCorrectionQueue, useExpertResolveCorrection } from "@/hooks/useCorrections";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { TableSkeleton } from "@/components/shared/LoadingSkeleton";
import { EmptyState } from "@/components/shared/EmptyState";
import { ShieldCheck, Inbox } from "lucide-react";

export function CorrectionsPage() {
  const { data, isLoading, error } = useExpertCorrectionQueue();
  const resolve = useExpertResolveCorrection();

  if (isLoading) return <TableSkeleton rows={6} />;
  if (error) {
    return (
      <EmptyState
        icon={ShieldCheck}
        title="Expert queue unavailable"
        description="Enable taxonomy_expert on your user profile to review corrections."
      />
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Species corrections</h1>
        <p className="text-sm text-muted-foreground">
          Review community-suggested ID fixes (taxonomy expert queue).
        </p>
      </div>

      {!data?.length ? (
        <EmptyState
          icon={Inbox}
          title="Queue empty"
          description="No open correction suggestions."
        />
      ) : (
        <div className="grid gap-4">
          {data.map((row) => (
            <Card key={row.id}>
              <CardHeader className="pb-2">
                <CardTitle className="text-base">
                  {row.proposed?.common_name ?? row.proposed?.scientific_name ?? "Species"}
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-3 text-sm">
                <p className="text-muted-foreground">{row.reason}</p>
                <p>
                  Reported by @{row.reporter?.username ?? "unknown"} ·{" "}
                  {new Date(row.created_at).toLocaleString()}
                </p>
                <div className="flex gap-2">
                  <Button
                    size="sm"
                    disabled={resolve.isPending}
                    onClick={() => resolve.mutate({ id: row.id, action: "accept" })}
                  >
                    Accept
                  </Button>
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={resolve.isPending}
                    onClick={() => resolve.mutate({ id: row.id, action: "reject" })}
                  >
                    Reject
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
