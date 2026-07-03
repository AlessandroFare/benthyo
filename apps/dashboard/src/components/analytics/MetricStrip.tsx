import { motion } from "framer-motion";
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
      {metrics.map((metric, i) => (
        <motion.button
          key={metric.id}
          type="button"
          onClick={metric.onClick}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: i * 0.06, duration: 0.25, ease: "easeOut" }}
          whileHover={metric.onClick ? { y: -2, transition: { duration: 0.18 } } : {}}
          whileTap={metric.onClick ? { scale: 0.98 } : {}}
          className={cn(
            "rounded-2xl border border-border bg-card px-5 py-4 text-left text-card-foreground transition-shadow",
            metric.active && "border-ocean-500/50 ring-1 ring-ocean-500/30 shadow-ocean-500/10 shadow-md",
            metric.onClick && "hover:border-ocean-500/40 hover:shadow-md cursor-pointer",
          )}
        >
          <p className="text-sm font-medium text-muted-foreground">{metric.label}</p>
          <p className="mt-1.5 text-2xl font-semibold text-foreground tabular-nums">
            {metric.value}
          </p>
          {metric.active && (
            <motion.div
              layoutId="metric-strip-indicator"
              className="mt-3 h-0.5 rounded-full bg-ocean-500"
            />
          )}
        </motion.button>
      ))}
    </div>
  );
}
