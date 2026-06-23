import { Link, useParams } from "react-router-dom";
import { ArrowLeft, Fish, MapPin } from "lucide-react";
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { useSpeciesDetail } from "@/hooks/useSpecies";
import { EmptyState } from "@/components/shared/EmptyState";
import { PageSkeleton } from "@/components/shared/LoadingSkeleton";
import { AnimatedPage, AnimatedItem } from "@/components/shared/AnimatedPage";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
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
import { formatNumber } from "@/lib/utils";

export function SpeciesDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { data: species, isLoading, isError, refetch } = useSpeciesDetail(id);

  if (isLoading) {
    return <PageSkeleton />;
  }

  if (isError || !species) {
    return (
      <div className="space-y-4">
        <Button variant="ghost" size="sm" asChild>
          <Link to="/species">
            <ArrowLeft className="mr-2 h-4 w-4" />
            Back to Species
          </Link>
        </Button>
        <EmptyState
          icon={Fish}
          title="Species not found"
          description="This species may not exist or you don't have access."
          actionLabel="Retry"
          onAction={() => refetch()}
        />
      </div>
    );
  }

  return (
    <AnimatedPage>
      <AnimatedItem>
      <Button variant="ghost" size="sm" asChild>
        <Link to="/species">
          <ArrowLeft className="mr-2 h-4 w-4" />
          Back to Species
        </Link>
      </Button>
      </AnimatedItem>

      <AnimatedItem>
      <div className="grid gap-6 lg:grid-cols-3">
        <Card className="lg:col-span-1">
          <CardHeader>
            <CardTitle className="italic">{species.scientific_name}</CardTitle>
            <CardDescription>
              {species.common_name ?? "No common name"}
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {species.photo_url && (
              <img
                src={species.photo_url}
                alt={species.common_name ?? species.scientific_name}
                className="aspect-video w-full rounded-lg object-cover"
              />
            )}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-sm text-muted-foreground">Sightings</p>
                <p className="text-lg font-semibold">
                  {formatNumber(species.sighting_count)}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Sites</p>
                <p className="text-lg font-semibold">
                  {formatNumber(species.site_count)}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Avg Depth</p>
                <p className="text-lg font-semibold">
                  {species.avg_depth_m ? `${species.avg_depth_m}m` : "—"}
                </p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Status</p>
                {species.conservation_status ? (
                  <Badge variant="outline">{species.conservation_status}</Badge>
                ) : (
                  <p className="text-lg font-semibold">—</p>
                )}
              </div>
            </div>
            {species.family && (
              <div>
                <p className="text-sm text-muted-foreground">Taxonomy</p>
                <p className="text-sm">
                  {[species.family, species.genus].filter(Boolean).join(" › ")}
                </p>
              </div>
            )}
            {species.description && (
              <div>
                <p className="text-sm text-muted-foreground">Description</p>
                <p className="text-sm">{species.description}</p>
              </div>
            )}
          </CardContent>
        </Card>

        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Monthly Trend</CardTitle>
            <CardDescription>Sighting frequency over time</CardDescription>
          </CardHeader>
          <CardContent>
            {species.monthly_trend.length === 0 ? (
              <EmptyState
                icon={Fish}
                title="No trend data"
                description="Monthly trends will appear as sightings accumulate."
                className="py-8"
              />
            ) : (
              <ResponsiveContainer width="100%" height={280}>
                <LineChart data={species.monthly_trend}>
                  <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
                  <XAxis dataKey="label" tick={{ fontSize: 12 }} />
                  <YAxis tick={{ fontSize: 12 }} />
                  <Tooltip />
                  <Line
                    type="monotone"
                    dataKey="value"
                    stroke="hsl(201, 96%, 32%)"
                    strokeWidth={2}
                  />
                </LineChart>
              </ResponsiveContainer>
            )}
          </CardContent>
        </Card>
      </div>
      </AnimatedItem>

      <AnimatedItem>
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <MapPin className="h-5 w-5" />
            Top Sites
          </CardTitle>
          <CardDescription>
            Dive sites with the most sightings of this species
          </CardDescription>
        </CardHeader>
        <CardContent>
          {species.top_sites.length === 0 ? (
            <EmptyState
              icon={MapPin}
              title="No site data"
              description="Site breakdowns will appear once sightings are logged."
              className="py-8"
            />
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Site</TableHead>
                  <TableHead className="text-right">Sightings</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {species.top_sites.map((site) => (
                  <TableRow key={site.id}>
                    <TableCell className="font-medium">{site.name}</TableCell>
                    <TableCell className="text-right">
                      {formatNumber(site.count)}
                    </TableCell>
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
