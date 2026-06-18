import { useState } from "react";
import { MapPin, Plus, Star, Trash2 } from "lucide-react";
import { useAddSite, useRemoveSite, useSites } from "@/hooks/useSites";
import { EmptyState } from "@/components/shared/EmptyState";
import { AnimatedPage, AnimatedItem } from "@/components/shared/AnimatedPage";
import { DataTable, type DataTableColumn } from "@/components/shared/DataTable";
import { ShimmerButton } from "@/components/shared/ShimmerButton";
import { useToast } from "@/components/shared/Toast";
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
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { formatDate, formatNumber } from "@/lib/utils";

type Site = NonNullable<ReturnType<typeof useSites>["data"]>[number];

export function SitesPage() {
  const { data: sites, isLoading, isError, refetch } = useSites();
  const addSite = useAddSite();
  const removeSite = useRemoveSite();
  const { toast } = useToast();

  const [dialogOpen, setDialogOpen] = useState(false);
  const [siteId, setSiteId] = useState("");
  const [removeId, setRemoveId] = useState<string | null>(null);

  async function handleAdd() {
    if (!siteId.trim()) return;
    try {
      await addSite.mutateAsync(siteId.trim());
      toast({ title: "Site added", description: "Linked to your operator account.", variant: "success" });
      setSiteId("");
      setDialogOpen(false);
    } catch (err) {
      toast({ title: "Could not add site", description: (err as Error).message, variant: "error" });
    }
  }

  async function handleRemove() {
    if (!removeId) return;
    const id = removeId;
    setRemoveId(null);
    try {
      await removeSite.mutateAsync(id);
      toast({ title: "Site removed", variant: "info" });
    } catch (err) {
      toast({ title: "Could not remove site", description: (err as Error).message, variant: "error" });
    }
  }

  if (isLoading) {
    return (
      <div className="space-y-6">
        <TableSkeleton rows={6} />
      </div>
    );
  }

  const columns: DataTableColumn<Site>[] = [
    {
      key: "name",
      header: "Name",
      cell: (s) => (
        <div className="flex items-center gap-2">
          <span className="font-medium text-white">{s.name}</span>
          {s.is_primary && (
            <Badge variant="warning" className="gap-1">
              <Star className="h-3 w-3" />
              Primary
            </Badge>
          )}
        </div>
      ),
      sortable: true,
      sortValue: (s) => s.name,
    },
    {
      key: "region",
      header: "Region",
      cell: (s) => `${s.region ?? ""}${s.country_code ? `, ${s.country_code}` : ""}`.replace(/^, /, "") || "—",
      sortable: true,
      sortValue: (s) => `${s.region} ${s.country_code}`,
    },
    {
      key: "difficulty",
      header: "Difficulty",
      cell: (s) => <Badge variant="outline">{s.difficulty}</Badge>,
      sortable: true,
    },
    {
      key: "depth_max",
      header: "Max Depth",
      cell: (s) => (s.depth_max ? `${s.depth_max}m` : "—"),
      sortable: true,
      align: "right",
      sortValue: (s) => s.depth_max,
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
      key: "added_at",
      header: "Added",
      cell: (s) => <span className="text-white/55">{formatDate(s.added_at)}</span>,
      sortable: true,
      sortValue: (s) => s.added_at,
    },
    {
      key: "actions",
      header: "",
      cell: (s) => (
        <Button
          variant="ghost"
          size="icon"
          onClick={(e) => {
            e.stopPropagation();
            setRemoveId(s.id);
          }}
          aria-label={`Remove ${s.name}`}
        >
          <Trash2 className="h-4 w-4 text-destructive" />
        </Button>
      ),
      align: "right",
      className: "w-12",
    },
  ];

  return (
    <AnimatedPage>
      <AnimatedItem className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold text-white">Operator Dive Sites</h2>
          <p className="text-sm text-white/45">
            Manage the dive sites linked to your operation
          </p>
        </div>
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <DialogTrigger asChild>
            <ShimmerButton>
              <Plus className="h-4 w-4" />
              Add Site
            </ShimmerButton>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Add Dive Site</DialogTitle>
              <DialogDescription>
                Enter the dive site ID to link it to your operator account.
              </DialogDescription>
            </DialogHeader>
            <div className="space-y-2">
              <Label htmlFor="site-id">Dive Site ID</Label>
              <Input
                id="site-id"
                placeholder="e.g. 550e8400-e29b-41d4-a716-446655440000"
                value={siteId}
                onChange={(e) => setSiteId(e.target.value)}
              />
            </div>
            <DialogFooter>
              <Button
                onClick={handleAdd}
                disabled={addSite.isPending || !siteId.trim()}
              >
                {addSite.isPending ? "Adding..." : "Add Site"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </AnimatedItem>

      <AnimatedItem>
        <Card>
          <CardHeader>
            <CardTitle>Linked Sites</CardTitle>
            <CardDescription>
              {sites?.length ?? 0} dive site{(sites?.length ?? 0) !== 1 ? "s" : ""}{" "}
              in your portfolio
            </CardDescription>
          </CardHeader>
          <CardContent>
            {isError ? (
              <EmptyState
                icon={MapPin}
                title="Failed to load sites"
                description="There was a problem fetching your dive sites."
                actionLabel="Retry"
                onAction={() => refetch()}
              />
            ) : (
              <DataTable
                data={sites ?? []}
                columns={columns}
                searchPlaceholder="Search by name, region, country…"
                emptyState={
                  <EmptyState
                    icon={MapPin}
                    title="No dive sites yet"
                    description="Add your first dive site to start tracking sightings and analytics."
                    actionLabel="Add Site"
                    onAction={() => setDialogOpen(true)}
                  />
                }
              />
            )}
          </CardContent>
        </Card>
      </AnimatedItem>

      <Dialog open={Boolean(removeId)} onOpenChange={() => setRemoveId(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Remove Dive Site</DialogTitle>
            <DialogDescription>
              This will unlink the site from your operator account. Existing
              dive logs will not be deleted.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRemoveId(null)}>
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={handleRemove}
              disabled={removeSite.isPending}
            >
              {removeSite.isPending ? "Removing..." : "Remove"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </AnimatedPage>
  );
}
