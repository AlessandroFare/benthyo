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
            "rounded-2xl border border-white/5 bg-[#161B22] px-5 py-4 text-left transition-colors",
            metric.active && "border-ocean-500/50 ring-1 ring-ocean-500/30",
            metric.onClick && "hover:border-white/10",
          )}
        >
          <p className="text-sm text-white/45">{metric.label}</p>
          <p className="mt-2 text-2xl font-semibold text-white">{metric.value}</p>
          {metric.active && (
            <div className="mt-3 h-0.5 rounded-full bg-ocean-500" />
          )}
        </button>
      ))}
    </div>
  );
}
