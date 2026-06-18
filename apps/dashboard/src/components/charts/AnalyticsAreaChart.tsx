import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import type { TimeSeriesPoint } from "@/lib/types";

interface AnalyticsAreaChartProps {
  data: TimeSeriesPoint[];
  label?: string;
}

export function AnalyticsAreaChart({
  data,
  label = "Sightings",
}: AnalyticsAreaChartProps) {
  return (
    <ResponsiveContainer width="100%" height={320}>
      <AreaChart data={data}>
        <defs>
          <linearGradient id="oceanAreaFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#0ea5e9" stopOpacity={0.35} />
            <stop offset="100%" stopColor="#0ea5e9" stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
        <XAxis
          dataKey="label"
          tick={{ fontSize: 12, fill: "rgba(255,255,255,0.45)" }}
          axisLine={false}
          tickLine={false}
        />
        <YAxis
          tick={{ fontSize: 12, fill: "rgba(255,255,255,0.45)" }}
          axisLine={false}
          tickLine={false}
        />
        <Tooltip
          contentStyle={{
            backgroundColor: "#161B22",
            border: "1px solid rgba(255,255,255,0.08)",
            borderRadius: 12,
            color: "#fff",
          }}
          labelStyle={{ color: "rgba(255,255,255,0.6)" }}
        />
        <Area
          type="monotone"
          dataKey="value"
          name={label}
          stroke="#0ea5e9"
          strokeWidth={2}
          fill="url(#oceanAreaFill)"
          dot={{ r: 3, fill: "#0ea5e9" }}
        />
      </AreaChart>
    </ResponsiveContainer>
  );
}
