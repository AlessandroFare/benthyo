import {
  Activity,
  Fish,
  MapPin,
  Users,
} from "lucide-react";
import { motion } from "framer-motion";
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import {
  useDashboardCharts,
  useDashboardKpis,
  useRecentActivity,
} from "@/hooks/useDashboard";
import { useChartTheme } from "@/hooks/useChartTheme";
import { KpiCard } from "@/components/dashboard/KpiCard";
import { EmptyState } from "@/components/shared/EmptyState";
import { AnimatedPage, AnimatedItem } from "@/components/shared/AnimatedPage";
import { StatusPill } from "@/components/shared/StatusPill";
import {
  ChartSkeleton,
  KpiSkeleton,
  TableSkeleton,
} from "@/components/shared/LoadingSkeleton";
import { Badge } from "@/components/ui/badge";
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
import { formatDateTime, formatNumber } from "@/lib/utils";

const activityTypeLabels: Record<string, string> = {
  sighting: "Sighting",
  dive: "Dive",
  customer: "Customer",
  site: "Site",
};

export function DashboardPage() {
  const kpisQuery = useDashboardKpis();
  const chartsQuery = useDashboardCharts();
  const activityQuery = useRecentActivity();
  const chart = useChartTheme();

  const isLoading =
    kpisQuery.isLoading || chartsQuery.isLoading || activityQuery.isLoading;

  if (isLoading) {
    return (
      <div className="space-y-6">
        <KpiSkeleton />
        <div className="grid gap-6 lg:grid-cols-2">
          <ChartSkeleton />
          <ChartSkeleton />
        </div>
        <TableSkeleton />
      </div>
    );
  }

  const kpis = kpisQuery.data;
  const charts = chartsQuery.data;
  const activity = activityQuery.data ?? [];

  const kpiCards = kpis
    ? [
        {
          label: "Total Sightings",
          value: kpis.total_sightings,
          sub: `${formatNumber(kpis.sightings_this_month)} this month`,
          icon: Fish,
          trend: kpis.sighting_change_pct,
          spark: charts?.sightings_trend.map((p) => p.value),
          accent: "primary" as const,
        },
        {
          label: "Dive Sites",
          value: kpis.total_sites,
          sub: kpis.top_site ? `Top: ${kpis.top_site.name}` : "No sites yet",
          icon: MapPin,
          accent: "info" as const,
        },
        {
          label: "Species Logged",
          value: kpis.total_species,
          sub: kpis.top_species
            ? `Top: ${kpis.top_species.name}`
            : "No species yet",
          icon: Activity,
          accent: "success" as const,
        },
        {
          label: "Customers",
          value: kpis.total_customers,
          sub: "Active divers",
          icon: Users,
          accent: "warning" as const,
        },
      ]
    : [];

  return (
    <AnimatedPage>
      <AnimatedItem className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-foreground">Dashboard</h1>
          <p className="mt-0.5 text-sm text-muted-foreground">
            Overview of your dive operation performance
          </p>
        </div>
        <div className="flex items-center gap-2">
          <StatusPill tone="success">Live data</StatusPill>
        </div>
      </AnimatedItem>

      <AnimatedItem>
        {kpisQuery.isError ? (
          <EmptyState
            icon={Activity}
            title="Unable to load KPIs"
            description="Check your API connection and try refreshing the page."
            actionLabel="Retry"
            onAction={() => kpisQuery.refetch()}
          />
        ) : (
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            {kpiCards.map((card) => (
              <KpiCard key={card.label} {...card} />
            ))}
          </div>
        )}
      </AnimatedItem>

      <AnimatedItem>
        <div className="grid gap-6 lg:grid-cols-2">
          <Card className="border-border bg-card text-foreground">
            <CardHeader>
              <CardTitle className="text-foreground">Sightings Trend</CardTitle>
              <CardDescription className="text-muted-foreground">
                Monthly sightings over time
              </CardDescription>
            </CardHeader>
            <CardContent>
              {chartsQuery.isError ? (
                <EmptyState
                  icon={Activity}
                  title="Chart unavailable"
                  description="Could not load sightings trend data."
                  actionLabel="Retry"
                  onAction={() => chartsQuery.refetch()}
                  className="py-8"
                />
              ) : charts?.sightings_trend.length ? (
                <ResponsiveContainer width="100%" height={280}>
                  <BarChart data={charts.sightings_trend}>
                    <CartesianGrid strokeDasharray="3 3" stroke={chart.gridStroke} />
                    <XAxis dataKey="label" tick={{ fontSize: 12, fill: chart.tickFill }} axisLine={false} tickLine={false} />
                    <YAxis tick={{ fontSize: 12, fill: chart.tickFill }} axisLine={false} tickLine={false} />
                    <Tooltip contentStyle={chart.tooltipStyle} labelStyle={chart.tooltipLabelStyle} />
                    <Bar dataKey="value" fill="#0ea5e9" radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              ) : (
                <EmptyState
                  icon={Fish}
                  title="No sightings data"
                  description="Sightings will appear here once divers start logging."
                  className="py-8"
                />
              )}
            </CardContent>
          </Card>

          <Card className="border-border bg-card text-foreground">
            <CardHeader>
              <CardTitle className="text-foreground">Dives by Site</CardTitle>
              <CardDescription className="text-muted-foreground">
                Top performing dive sites
              </CardDescription>
            </CardHeader>
            <CardContent>
              {chartsQuery.isError ? (
                <EmptyState
                  icon={MapPin}
                  title="Chart unavailable"
                  description="Could not load dive site data."
                  actionLabel="Retry"
                  onAction={() => chartsQuery.refetch()}
                  className="py-8"
                />
              ) : charts?.dives_by_site.length ? (
                <ResponsiveContainer width="100%" height={280}>
                  <BarChart data={charts.dives_by_site}>
                    <CartesianGrid strokeDasharray="3 3" stroke={chart.gridStroke} />
                    <XAxis dataKey="label" tick={{ fontSize: 11, fill: chart.tickFill }} axisLine={false} tickLine={false} />
                    <YAxis tick={{ fontSize: 12, fill: chart.tickFill }} axisLine={false} tickLine={false} />
                    <Tooltip contentStyle={chart.tooltipStyle} labelStyle={chart.tooltipLabelStyle} />
                    <Bar dataKey="value" fill="#38bdf8" radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              ) : (
                <EmptyState
                  icon={MapPin}
                  title="No dive data"
                  description="Add dive sites to start tracking performance."
                  className="py-8"
                />
              )}
            </CardContent>
          </Card>
        </div>
      </AnimatedItem>

      <AnimatedItem>
        <Card className="border-border bg-card text-foreground">
          <CardHeader>
            <CardTitle className="text-foreground">Recent Activity</CardTitle>
            <CardDescription className="text-muted-foreground">
              Latest events across your operation
            </CardDescription>
          </CardHeader>
          <CardContent>
            {activityQuery.isError ? (
              <EmptyState
                icon={Activity}
                title="Activity feed unavailable"
                description="Could not load recent activity."
                actionLabel="Retry"
                onAction={() => activityQuery.refetch()}
              />
            ) : activity.length === 0 ? (
              <EmptyState
                icon={Activity}
                title="No recent activity"
                description="Activity from dives, sightings, and customers will show up here."
              />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow className="border-border hover:bg-transparent">
                    <TableHead className="text-muted-foreground">Type</TableHead>
                    <TableHead className="text-muted-foreground">Event</TableHead>
                    <TableHead className="text-muted-foreground">Details</TableHead>
                    <TableHead className="text-right text-muted-foreground">When</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {activity.map((item, i) => (
                    <motion.tr
                      key={item.id}
                      initial={{ opacity: 0, y: 4 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={{ delay: i * 0.03, duration: 0.22, ease: "easeOut" }}
                      className={`border-border transition-colors hover:bg-accent/40 ${i % 2 === 0 ? "" : "bg-muted/30"}`}
                    >
                      <TableCell>
                        <Badge variant="secondary" className="text-foreground">
                          {activityTypeLabels[item.type] ?? item.type}
                        </Badge>
                      </TableCell>
                      <TableCell className="font-medium text-foreground">{item.title}</TableCell>
                      <TableCell className="text-muted-foreground">{item.description}</TableCell>
                      <TableCell className="text-right text-muted-foreground">
                        {formatDateTime(item.occurred_at)}
                      </TableCell>
                    </motion.tr>
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
