import { cn } from "@/lib/utils";

interface MetricStripProps {
  metrics: Array<{
    id: string;
    label: string;
    value: string;
    active?: boolean;
    onClick?: () => void;
  }>;
}

export function MetricStrip({ metrics }: MetricStripProps) {
  return (
    <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
      {metrics.map((metric) => (
        <button
          key={metric.id}
          type="button"
          onClick={metric.onClick}
          className={cn(
            "rounded-2xl border border-border bg-card px-5 py-4 text-left text-card-foreground transition-colors",
            metric.active && "border-ocean-500/50 ring-1 ring-ocean-500/30",
            metric.onClick && "hover:border-ocean-500/40",
          )}
        >
          <p className="text-sm text-muted-foreground">{metric.label}</p>
          <p className="mt-2 text-2xl font-semibold text-foreground">{metric.value}</p>
          {metric.active && (
            <div className="mt-3 h-0.5 rounded-full bg-ocean-500" />
          )}
        </button>
      ))}
    </div>
  );
}
