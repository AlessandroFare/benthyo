import { Link, useParams } from "react-router-dom";
import { ArrowLeft, Fish, MapPin, Users } from "lucide-react";
import { useCustomer } from "@/hooks/useCustomers";
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
import { formatDate, formatNumber } from "@/lib/utils";

export function CustomerDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { data: customer, isLoading, isError, refetch } = useCustomer(id);

  if (isLoading) {
    return <PageSkeleton />;
  }

  if (isError || !customer) {
    return (
      <div className="space-y-4">
        <Button variant="ghost" size="sm" asChild>
          <Link to="/customers">
            <ArrowLeft className="mr-2 h-4 w-4" />
            Back to Customers
          </Link>
        </Button>
        <EmptyState
          icon={Users}
          title="Customer not found"
          description="This customer may have been removed or you don't have access."
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
        <Link to="/customers">
          <ArrowLeft className="mr-2 h-4 w-4" />
          Back to Customers
        </Link>
      </Button>
      </AnimatedItem>

      <AnimatedItem>
      <div className="grid gap-6 lg:grid-cols-3">
        <Card className="lg:col-span-1">
          <CardHeader>
            <CardTitle>
              {customer.first_name} {customer.last_name}
            </CardTitle>
            <CardDescription>{customer.email}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div>
              <p className="text-sm text-muted-foreground">Certification</p>
              <p className="font-medium">
                {customer.certification_level ?? "Not specified"}
              </p>
            </div>
            <div>
              <p className="text-sm text-muted-foreground">Total Dives</p>
              <p className="font-medium">{formatNumber(customer.total_dives)}</p>
            </div>
            <div>
              <p className="text-sm text-muted-foreground">Last Dive</p>
              <p className="font-medium">{formatDate(customer.last_dive_at)}</p>
            </div>
            {customer.tags.length > 0 && (
              <div>
                <p className="mb-2 text-sm text-muted-foreground">Tags</p>
                <div className="flex flex-wrap gap-1">
                  {customer.tags.map((tag) => (
                    <Badge key={tag} variant="secondary">
                      {tag}
                    </Badge>
                  ))}
                </div>
              </div>
            )}
          </CardContent>
        </Card>

        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <MapPin className="h-5 w-5" />
              Recent Dives
            </CardTitle>
          </CardHeader>
          <CardContent>
            {customer.recent_dives.length === 0 ? (
              <EmptyState
                icon={MapPin}
                title="No dives logged"
                description="This customer hasn't logged any dives yet."
                className="py-8"
              />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Site</TableHead>
                    <TableHead>Date</TableHead>
                    <TableHead>Max Depth</TableHead>
                    <TableHead>Duration</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {customer.recent_dives.map((dive) => (
                    <TableRow key={dive.id}>
                      <TableCell className="font-medium">
                        {dive.dive_site_name}
                      </TableCell>
                      <TableCell>{formatDate(dive.dive_date)}</TableCell>
                      <TableCell>{dive.max_depth_m}m</TableCell>
                      <TableCell>{dive.duration_min} min</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>
      </AnimatedItem>

      <AnimatedItem>
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Fish className="h-5 w-5" />
            Species Seen
          </CardTitle>
          <CardDescription>
            Life list entries from this customer
          </CardDescription>
        </CardHeader>
        <CardContent>
          {customer.species_seen.length === 0 ? (
            <EmptyState
              icon={Fish}
              title="No species sightings"
              description="Species sightings will appear here as the customer logs dives."
              className="py-8"
            />
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Species</TableHead>
                  <TableHead>Sightings</TableHead>
                  <TableHead>Last Seen</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {customer.species_seen.map((species) => (
                  <TableRow key={species.id}>
                    <TableCell className="font-medium">{species.name}</TableCell>
                    <TableCell>{formatNumber(species.sighting_count)}</TableCell>
                    <TableCell className="text-muted-foreground">
                      {formatDate(species.last_seen_at)}
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
