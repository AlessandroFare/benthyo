import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { useTheme } from "@/contexts/ThemeContext";
import type { TimeSeriesPoint } from "@/lib/types";

interface AnalyticsAreaChartProps {
  data: TimeSeriesPoint[];
  label?: string;
}

export function AnalyticsAreaChart({
  data,
  label = "Sightings",
}: AnalyticsAreaChartProps) {
  const { resolvedTheme } = useTheme();
  const isDark = resolvedTheme === "dark";

  const gridStroke = isDark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.06)";
  const tickFill = isDark ? "rgba(255,255,255,0.45)" : "rgba(0,0,0,0.45)";
  const tooltipBg = isDark ? "hsl(213 22% 12%)" : "hsl(0 0% 100%)";
  const tooltipBorder = isDark
    ? "1px solid rgba(255,255,255,0.08)"
    : "1px solid rgba(0,0,0,0.1)";
  const tooltipColor = isDark ? "#fff" : "#111";
  const tooltipLabelColor = isDark ? "rgba(255,255,255,0.6)" : "rgba(0,0,0,0.5)";

  return (
    <ResponsiveContainer width="100%" height={320}>
      <AreaChart data={data}>
        <defs>
          <linearGradient id="oceanAreaFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#0ea5e9" stopOpacity={0.35} />
            <stop offset="100%" stopColor="#0ea5e9" stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" stroke={gridStroke} />
        <XAxis
          dataKey="label"
          tick={{ fontSize: 12, fill: tickFill }}
          axisLine={false}
          tickLine={false}
        />
        <YAxis
          tick={{ fontSize: 12, fill: tickFill }}
          axisLine={false}
          tickLine={false}
        />
        <Tooltip
          contentStyle={{
            backgroundColor: tooltipBg,
            border: tooltipBorder,
            borderRadius: 12,
            color: tooltipColor,
            boxShadow: "0 8px 24px rgba(0,0,0,0.15)",
          }}
          labelStyle={{ color: tooltipLabelColor }}
        />
        <Area
          type="monotone"
          dataKey="value"
          name={label}
          stroke="#0ea5e9"
          strokeWidth={2}
          fill="url(#oceanAreaFill)"
          dot={{ r: 3, fill: "#0ea5e9" }}
          activeDot={{ r: 5, fill: "#0ea5e9", strokeWidth: 0 }}
        />
      </AreaChart>
    </ResponsiveContainer>
  );
}
