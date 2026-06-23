import { ArrowDown, ArrowUp, type LucideIcon } from "lucide-react";
import { motion } from "framer-motion";
import { Card, CardContent } from "@/components/ui/card";
import { AnimatedNumber } from "@/components/shared/AnimatedNumber";
import { cn } from "@/lib/utils";

interface KpiCardProps {
  label: string;
  value: string | number;
  sub?: string;
  icon: LucideIcon;
  /** Optional sparkline data points (numbers, e.g. last 12 months). */
  spark?: number[];
  /** Percent change vs. previous period. */
  trend?: number;
  /** Accent color for the sparkline. */
  accent?: "primary" | "success" | "warning" | "info";
  /** Optional click handler — makes the card an interactive surface. */
  onClick?: () => void;
  /** Decimals for AnimatedNumber (when value is a number). */
  decimals?: number;
}

const ACCENT_HEX: Record<NonNullable<KpiCardProps["accent"]>, string> = {
  primary: "#0ea5e9",
  success: "#22c55e",
  warning: "#f59e0b",
  info: "#38bdf8",
};

/**
 * Animated KPI card with a hand-drawn SVG sparkline. The card lifts
 * slightly on hover and the sparkline is drawn from left to right on
 * mount. The trend chip is green for positive, red for negative.
 */
export function KpiCard({
  label,
  value,
  sub,
  icon: Icon,
  spark,
  trend,
  accent = "primary",
  onClick,
  decimals = 0,
}: KpiCardProps) {
  const positive = (trend ?? 0) >= 0;
  const color = ACCENT_HEX[accent];

  // Path for the sparkline. We always show 12 buckets; the bar height
  // is normalised to the max value.
  const sparkline = (spark ?? []).slice(-12);
  const max = Math.max(1, ...sparkline);
  const w = 120;
  const h = 36;
  const stepX = sparkline.length > 1 ? w / (sparkline.length - 1) : w;
  const points = sparkline
    .map((v, i) => {
      const x = i * stepX;
      const y = h - (v / max) * h;
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");

  // We compute the dash length for the line-draw animation. SVG
  // strokes don't auto-compute their length in older browsers, so we
  // approximate by adding 50% headroom.
  const totalPathLen = w + h * 2;

  return (
    <motion.div
      whileHover={{ y: -2, transition: { duration: 0.18 } }}
      whileTap={{ scale: 0.98 }}
      onClick={onClick}
      className={cn(onClick && "cursor-pointer")}
    >
      <Card className="border-border bg-card text-card-foreground">
        <CardContent className="p-5">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0 flex-1">
              <div className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
                {label}
              </div>
              <div className="mt-1.5 flex items-baseline gap-2">
                <motion.div
                  initial={{ opacity: 0, y: 6 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.32, ease: "easeOut" }}
                  className="text-2xl font-semibold tracking-tight"
                >
                  {typeof value === "number" ? (
                    <AnimatedNumber value={value} decimals={decimals} />
                  ) : (
                    value
                  )}
                </motion.div>
                {typeof trend === "number" && (
                  <span
                    className={cn(
                      "inline-flex items-center gap-0.5 rounded-md px-1.5 py-0.5 text-[10px] font-medium",
                      positive
                        ? "bg-emerald-500/15 text-emerald-300"
                        : "bg-rose-500/15 text-rose-300",
                    )}
                  >
                    {positive ? (
                      <ArrowUp className="h-2.5 w-2.5" />
                    ) : (
                      <ArrowDown className="h-2.5 w-2.5" />
                    )}
                    {Math.abs(trend).toFixed(0)}%
                  </span>
                )}
              </div>
              {sub && (
                <div className="mt-1 text-xs text-muted-foreground">{sub}</div>
              )}
            </div>
            <div
              className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg"
              style={{ backgroundColor: `${color}1f` }}
            >
              <Icon className="h-5 w-5" style={{ color }} />
            </div>
          </div>
          {sparkline.length > 1 && (
            <svg
              className="mt-4 h-9 w-full"
              viewBox={`0 0 ${w} ${h}`}
              preserveAspectRatio="none"
              aria-hidden="true"
            >
              <motion.polyline
                points={points}
                fill="none"
                stroke={color}
                strokeWidth={1.6}
                strokeLinecap="round"
                strokeLinejoin="round"
                initial={{ pathLength: 0 }}
                animate={{ pathLength: 1 }}
                transition={{ duration: 0.9, ease: "easeOut", delay: 0.1 }}
                style={{ strokeDasharray: totalPathLen }}
              />
            </svg>
          )}
        </CardContent>
      </Card>
    </motion.div>
  );
}
