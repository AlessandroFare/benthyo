import { useState } from "react";
import { BarChart3 } from "lucide-react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { useAnalytics } from "@/hooks/useAnalytics";
import { useChartTheme } from "@/hooks/useChartTheme";
import { useDashboardCharts, useDashboardKpis } from "@/hooks/useDashboard";
import { MetricStrip } from "@/components/analytics/MetricStrip";
import { AnalyticsAreaChart } from "@/components/charts/AnalyticsAreaChart";
import { AnimatedPage, AnimatedItem } from "@/components/shared/AnimatedPage";
import { EmptyState } from "@/components/shared/EmptyState";
import { PageSkeleton } from "@/components/shared/LoadingSkeleton";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { cn, formatNumber } from "@/lib/utils";

const HEATMAP_COLORS = [
  "bg-white/5",
  "bg-ocean-900/40",
  "bg-ocean-700/50",
  "bg-ocean-500/60",
  "bg-ocean-400/80",
];

const PIE_COLORS = ["#0ea5e9", "#0284c7", "#0369a1", "#075985", "#38bdf8", "#7dd3fc"];

const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function getHeatmapIntensity(value: number, max: number): number {
  if (max === 0) return 0;
  const ratio = value / max;
  if (ratio === 0) return 0;
  if (ratio < 0.25) return 1;
  if (ratio < 0.5) return 2;
  if (ratio < 0.75) return 3;
  return 4;
}

export function AnalyticsPage() {
  const [activeMetric, setActiveMetric] = useState("sightings");
  const kpisQuery = useDashboardKpis();
  const chartsQuery = useDashboardCharts();
  const { data, isLoading, isError, refetch } = useAnalytics();
  const chart = useChartTheme();

  if (isLoading || kpisQuery.isLoading || chartsQuery.isLoading) {
    return <PageSkeleton />;
  }

  if (isError || !data || !kpisQuery.data || !chartsQuery.data) {
    return (
      <EmptyState
        icon={BarChart3}
        title="Analytics unavailable"
        description="Could not load analytics data. Check your API connection."
        actionLabel="Retry"
        onAction={() => {
          refetch();
          kpisQuery.refetch();
          chartsQuery.refetch();
        }}
      />
    );
  }

  const kpis = kpisQuery.data;
  const charts = chartsQuery.data;
  const maxHeatmap = Math.max(...data.heatmap.map((c) => c.value), 1);

  const heatmapGrid = Array.from({ length: 7 }, (_, day) =>
    Array.from({ length: 24 }, (_, hour) => {
      const cell = data.heatmap.find((c) => c.day === day && c.hour === hour);
      return cell?.value ?? 0;
    }),
  );

  const metrics = [
    {
      id: "sightings",
      label: "Sightings",
      value: formatNumber(kpis.total_sightings),
      active: activeMetric === "sightings",
      onClick: () => setActiveMetric("sightings"),
    },
    {
      id: "sites",
      label: "Active Sites",
      value: formatNumber(kpis.total_sites),
      active: activeMetric === "sites",
      onClick: () => setActiveMetric("sites"),
    },
    {
      id: "species",
      label: "Species",
      value: formatNumber(kpis.total_species),
      active: activeMetric === "species",
      onClick: () => setActiveMetric("species"),
    },
    {
      id: "customers",
      label: "Customers",
      value: formatNumber(kpis.total_customers),
      active: activeMetric === "customers",
      onClick: () => setActiveMetric("customers"),
    },
  ];

  const chartData =
    activeMetric === "sites"
      ? charts.dives_by_site
      : charts.sightings_trend;

  const chartLabel =
    activeMetric === "sites" ? "Dives by site" : "Sightings trend";

  return (
    <AnimatedPage>
      <AnimatedItem>
        <div>
          <h1 className="text-2xl font-semibold text-foreground">Analytics</h1>
          <p className="text-sm text-muted-foreground">
            Insights and trends across your operation
          </p>
        </div>
      </AnimatedItem>

      <AnimatedItem>
        <MetricStrip metrics={metrics} />
      </AnimatedItem>

      <AnimatedItem>
      <Card className="border-border bg-card text-foreground">
        <CardHeader>
          <CardTitle className="text-foreground">{chartLabel}</CardTitle>
          <CardDescription className="text-muted-foreground">
            Select a metric above to explore trends
          </CardDescription>
        </CardHeader>
        <CardContent>
          {chartData.length === 0 ? (
            <EmptyState
              icon={BarChart3}
              title="No trend data"
              description="Trends will appear once activity is logged."
              className="py-8"
            />
          ) : activeMetric === "sites" ? (
            <ResponsiveContainer width="100%" height={320}>
              <BarChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" stroke={chart.gridStroke} />
                <XAxis dataKey="label" tick={{ fontSize: 11, fill: chart.tickFill }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 12, fill: chart.tickFill }} axisLine={false} tickLine={false} />
                <Tooltip contentStyle={chart.tooltipStyle} labelStyle={chart.tooltipLabelStyle} />
                <Bar dataKey="value" fill="#0ea5e9" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          ) : (
            <AnalyticsAreaChart data={chartData} label={chartLabel} />
          )}
        </CardContent>
      </Card>
      </AnimatedItem>

      <AnimatedItem>
      <Card className="border-border bg-card text-foreground">
        <CardHeader>
          <CardTitle className="text-foreground">Activity Heatmap</CardTitle>
          <CardDescription className="text-muted-foreground">
            Dive and sighting activity by day and hour
          </CardDescription>
        </CardHeader>
        <CardContent>
          {data.heatmap.length === 0 ? (
            <EmptyState
              icon={BarChart3}
              title="No activity data"
              description="Activity patterns will appear once divers start logging."
              className="py-8"
            />
          ) : (
            <div className="overflow-x-auto">
              <div className="inline-block min-w-full">
                <div className="mb-2 flex pl-12 text-xs text-muted-foreground">
                  {Array.from({ length: 24 }, (_, h) => (
                    <div key={h} className="w-4 text-center">
                      {h % 6 === 0 ? `${h}h` : ""}
                    </div>
                  ))}
                </div>
                {heatmapGrid.map((row, day) => (
                  <div key={day} className="flex items-center gap-1">
                    <span className="w-10 text-xs text-muted-foreground">{DAYS[day]}</span>
                    <div className="flex gap-0.5">
                      {row.map((value, hour) => (
                        <div
                          key={hour}
                          title={`${DAYS[day]} ${hour}:00 — ${value} events`}
                          className={cn(
                            "h-4 w-4 rounded-sm",
                            HEATMAP_COLORS[getHeatmapIntensity(value, maxHeatmap)],
                          )}
                        />
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </CardContent>
      </Card>
      </AnimatedItem>

      <AnimatedItem>
      <div className="grid gap-6 lg:grid-cols-2">
        <Card className="border-border bg-card text-foreground">
          <CardHeader>
            <CardTitle className="text-foreground">Species Diversity</CardTitle>
            <CardDescription className="text-muted-foreground">
              Distribution by taxonomic family
            </CardDescription>
          </CardHeader>
          <CardContent>
            {data.diversity.length === 0 ? (
              <EmptyState
                icon={BarChart3}
                title="No diversity data"
                description="Species diversity charts will populate from sightings."
                className="py-8"
              />
            ) : (
              <ResponsiveContainer width="100%" height={300}>
                <PieChart>
                  <Pie
                    data={data.diversity}
                    dataKey="count"
                    nameKey="family"
                    cx="50%"
                    cy="50%"
                    outerRadius={100}
                    label={({ family, percentage }) =>
                      `${family} (${percentage.toFixed(0)}%)`
                    }
                  >
                    {data.diversity.map((_, i) => (
                      <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip contentStyle={chart.tooltipStyle} labelStyle={chart.tooltipLabelStyle} />
                </PieChart>
              </ResponsiveContainer>
            )}
          </CardContent>
        </Card>

        <Card className="border-border bg-card text-foreground">
          <CardHeader>
            <CardTitle className="text-foreground">Depth Histogram</CardTitle>
            <CardDescription className="text-muted-foreground">
              Sighting depth distribution
            </CardDescription>
          </CardHeader>
          <CardContent>
            {data.depth_histogram.length === 0 ? (
              <EmptyState
                icon={BarChart3}
                title="No depth data"
                description="Depth histograms require sighting depth records."
                className="py-8"
              />
            ) : (
              <ResponsiveContainer width="100%" height={300}>
                <BarChart data={data.depth_histogram}>
                  <CartesianGrid strokeDasharray="3 3" stroke={chart.gridStroke} />
                  <XAxis dataKey="depth_range" tick={{ fontSize: 11, fill: chart.tickFill }} axisLine={false} tickLine={false} />
                  <YAxis tick={{ fontSize: 12, fill: chart.tickFill }} axisLine={false} tickLine={false} />
                  <Tooltip contentStyle={chart.tooltipStyle} labelStyle={chart.tooltipLabelStyle} />
                  <Bar dataKey="count" fill="#38bdf8" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            )}
          </CardContent>
        </Card>
      </div>
      </AnimatedItem>

      <AnimatedItem>
      <Card className="border-border bg-card text-foreground">
        <CardHeader>
          <CardTitle className="text-foreground">Customer Retention</CardTitle>
          <CardDescription className="text-muted-foreground">
            Monthly cohort retention rates (%)
          </CardDescription>
        </CardHeader>
        <CardContent>
          {data.retention.length === 0 ? (
            <EmptyState
              icon={BarChart3}
              title="No retention data"
              description="Retention cohorts need at least one month of customer activity."
              className="py-8"
            />
          ) : (
            <Table>
              <TableHeader>
                <TableRow className="border-border hover:bg-transparent">
                  <TableHead className="text-muted-foreground">Cohort</TableHead>
                  <TableHead className="text-muted-foreground">Month 0</TableHead>
                  <TableHead className="text-muted-foreground">Month 1</TableHead>
                  <TableHead className="text-muted-foreground">Month 2</TableHead>
                  <TableHead className="text-muted-foreground">Month 3</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.retention.map((row) => (
                  <TableRow key={row.cohort} className="border-border">
                    <TableCell className="font-medium text-foreground">{row.cohort}</TableCell>
                    <TableCell className="text-muted-foreground">{formatNumber(row.month_0)}%</TableCell>
                    <TableCell className="text-muted-foreground">{formatNumber(row.month_1)}%</TableCell>
                    <TableCell className="text-muted-foreground">{formatNumber(row.month_2)}%</TableCell>
                    <TableCell className="text-muted-foreground">{formatNumber(row.month_3)}%</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
      </AnimatedItem>
    </AnimatedPage>
  );
}
