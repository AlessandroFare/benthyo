import { useState } from "react";
import { Link } from "react-router-dom";
import { ChevronRight, Search, Users } from "lucide-react";
import { useCustomers } from "@/hooks/useCustomers";
import { EmptyState } from "@/components/shared/EmptyState";
import { TableSkeleton } from "@/components/shared/LoadingSkeleton";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatDate, formatNumber } from "@/lib/utils";

export function CustomersPage() {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState("");
  const [searchInput, setSearchInput] = useState("");

  const { data, isLoading, isError, refetch } = useCustomers(page, search);

  function handleSearch(e: React.FormEvent) {
    e.preventDefault();
    setSearch(searchInput);
    setPage(1);
  }

  if (isLoading) {
    return <TableSkeleton rows={8} />;
  }

  const customers = data?.data ?? [];
  const totalPages = data ? Math.ceil(data.total / data.page_size) : 0;

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h2 className="text-lg font-semibold">Customers</h2>
          <p className="text-sm text-muted-foreground">
            Divers associated with your operation
          </p>
        </div>
        <form onSubmit={handleSearch} className="relative w-full sm:w-72">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Search by name or email..."
            className="pl-9"
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
          />
        </form>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>All Customers</CardTitle>
          <CardDescription>
            {data ? `${formatNumber(data.total)} total customers` : "—"}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {isError ? (
            <EmptyState
              icon={Users}
              title="Failed to load customers"
              description="There was a problem fetching customer data."
              actionLabel="Retry"
              onAction={() => refetch()}
            />
          ) : customers.length === 0 ? (
            <EmptyState
              icon={Users}
              title={search ? "No matches found" : "No customers yet"}
              description={
                search
                  ? "Try a different search term."
                  : "Customers will appear here when divers log dives with your operation."
              }
              actionLabel={search ? "Clear search" : undefined}
              onAction={search ? () => { setSearch(""); setSearchInput(""); } : undefined}
            />
          ) : (
            <>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Name</TableHead>
                    <TableHead>Email</TableHead>
                    <TableHead>Certification</TableHead>
                    <TableHead>Total Dives</TableHead>
                    <TableHead>Last Dive</TableHead>
                    <TableHead>Tags</TableHead>
                    <TableHead />
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {customers.map((customer) => (
                    <TableRow key={customer.id}>
                      <TableCell className="font-medium">
                        {customer.first_name} {customer.last_name}
                      </TableCell>
                      <TableCell className="text-muted-foreground">
                        {customer.email}
                      </TableCell>
                      <TableCell>
                        {customer.certification_level ?? "—"}
                      </TableCell>
                      <TableCell>{formatNumber(customer.total_dives)}</TableCell>
                      <TableCell className="text-muted-foreground">
                        {formatDate(customer.last_dive_at)}
                      </TableCell>
                      <TableCell>
                        <div className="flex flex-wrap gap-1">
                          {customer.tags.slice(0, 2).map((tag) => (
                            <Badge key={tag} variant="secondary">
                              {tag}
                            </Badge>
                          ))}
                          {customer.tags.length > 2 && (
                            <Badge variant="outline">
                              +{customer.tags.length - 2}
                            </Badge>
                          )}
                        </div>
                      </TableCell>
                      <TableCell>
                        <Button variant="ghost" size="sm" asChild>
                          <Link to={`/customers/${customer.id}`}>
                            View
                            <ChevronRight className="ml-1 h-4 w-4" />
                          </Link>
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>

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
            </>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
