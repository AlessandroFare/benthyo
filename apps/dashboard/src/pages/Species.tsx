import { useState } from "react";
import { Link } from "react-router-dom";
import { ChevronRight, Fish } from "lucide-react";
import { useSpecies } from "@/hooks/useSpecies";
import { EmptyState } from "@/components/shared/EmptyState";
import { AnimatedPage, AnimatedItem } from "@/components/shared/AnimatedPage";
import { DataTable, type DataTableColumn } from "@/components/shared/DataTable";
import { TableSkeleton } from "@/components/shared/LoadingSkeleton";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { formatDate, formatNumber } from "@/lib/utils";

type SpeciesRow = NonNullable<ReturnType<typeof useSpecies>["data"]>["data"][number];

export function SpeciesPage() {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState("");
  const [searchInput, setSearchInput] = useState("");

  const { data, isLoading, isError, refetch } = useSpecies(page, search);

  function handleSearch(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setSearch(searchInput);
    setPage(1);
  }

  if (isLoading) {
    return <TableSkeleton rows={10} />;
  }

  const species = data?.data ?? [];
  const totalPages = data ? Math.ceil(data.total / data.page_size) : 0;

  const columns: DataTableColumn<SpeciesRow>[] = [
    {
      key: "rank",
      header: "#",
      cell: (s) => (
        <span className="font-medium text-foreground/40">
          {/* DataTable supplies the index via the row's id ordering;
              we re-derive the absolute page rank from the row's
              sighting_count which is stable. */}
          {formatNumber(s.sighting_count)}
        </span>
      ),
      sortable: false,
      align: "left",
      className: "w-12",
    },
    {
      key: "scientific_name",
      header: "Species",
      cell: (s) => (
        <div>
          <p className="font-medium italic text-foreground">{s.scientific_name}</p>
          {s.common_name && (
            <p className="text-sm text-muted-foreground">{s.common_name}</p>
          )}
        </div>
      ),
      sortable: true,
      sortValue: (s) => s.scientific_name,
    },
    {
      key: "family",
      header: "Family",
      cell: (s) => s.family ?? "—",
      sortable: true,
      sortValue: (s) => s.family,
    },
    {
      key: "sighting_count",
      header: "Sightings",
      cell: (s) => formatNumber(s.sighting_count),
      sortable: true,
      align: "right",
      sortValue: (s) => s.sighting_count,
    },
    {
      key: "site_count",
      header: "Sites",
      cell: (s) => formatNumber(s.site_count),
      sortable: true,
      align: "right",
      sortValue: (s) => s.site_count,
    },
    {
      key: "last_seen_at",
      header: "Last Seen",
      cell: (s) => <span className="text-foreground/55">{formatDate(s.last_seen_at)}</span>,
      sortable: true,
      sortValue: (s) => s.last_seen_at,
    },
    {
      key: "conservation_status",
      header: "Status",
      cell: (s) =>
        s.conservation_status ? <Badge variant="outline">{s.conservation_status}</Badge> : "—",
      sortable: true,
      sortValue: (s) => s.conservation_status,
    },
    {
      key: "actions",
      header: "",
      cell: (s) => (
        <Button variant="ghost" size="sm" asChild>
          <Link to={`/species/${s.id}`}>
            View
            <ChevronRight className="ml-1 h-4 w-4" />
          </Link>
        </Button>
      ),
      align: "right",
    },
  ];

  return (
    <AnimatedPage>
      <AnimatedItem className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-lg font-semibold text-foreground">Species Rankings</h2>
          <p className="text-sm text-muted-foreground">
            Most frequently sighted species across your sites
          </p>
        </div>
        <form onSubmit={handleSearch} className="relative w-full sm:w-72">
          <Input
            placeholder="Search species..."
            className="pl-3"
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
          />
        </form>
      </AnimatedItem>

      <AnimatedItem>
        <Card>
          <CardHeader>
            <CardTitle>Ranked Species</CardTitle>
            <CardDescription>
              {data ? `${formatNumber(data.total)} species recorded` : "—"}
            </CardDescription>
          </CardHeader>
          <CardContent>
            {isError ? (
              <EmptyState
                icon={Fish}
                title="Failed to load species"
                description="There was a problem fetching species data."
                actionLabel="Retry"
                onAction={() => refetch()}
              />
            ) : (
              <DataTable
                data={species}
                columns={columns}
                searchPlaceholder="Quick filter…"
                emptyState={
                  <EmptyState
                    icon={Fish}
                    title={search ? "No matches found" : "No species recorded"}
                    description={
                      search
                        ? "Try a different search term."
                        : "Species will appear as divers log sightings at your sites."
                    }
                    actionLabel={search ? "Clear search" : undefined}
                    onAction={search ? () => { setSearch(""); setSearchInput(""); } : undefined}
                  />
                }
              />
            )}

            {totalPages > 1 && (
              <div className="mt-4 flex items-center justify-between">
                <p className="text-sm text-muted-foreground">
                  Page {page} of {totalPages}
                </p>
                <div className="flex gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={page <= 1}
                    onClick={() => setPage((p) => p - 1)}
                  >
                    Previous
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={page >= totalPages}
                    onClick={() => setPage((p) => p + 1)}
                  >
                    Next
                  </Button>
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      </AnimatedItem>
    </AnimatedPage>
  );
}
