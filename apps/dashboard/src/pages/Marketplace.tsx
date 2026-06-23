import { useState } from "react";
import {
  useCreateMarketplaceListing,
  useOperatorMarketplace,
  useUpdateMarketplaceListing,
} from "@/hooks/useMarketplace";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { TableSkeleton } from "@/components/shared/LoadingSkeleton";
import { AnimatedPage, AnimatedItem } from "@/components/shared/AnimatedPage";
import { EmptyState } from "@/components/shared/EmptyState";
import { Store } from "lucide-react";

export function MarketplacePage() {
  const { data, isLoading, isError, refetch } = useOperatorMarketplace();
  const createListing = useCreateMarketplaceListing();
  const updateListing = useUpdateMarketplaceListing();

  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [price, setPrice] = useState("89");
  const [listingType, setListingType] = useState("fun_dive");
  const [region, setRegion] = useState("");

  if (isLoading) return <TableSkeleton rows={6} />;

  return (
    <AnimatedPage>
      <AnimatedItem>
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Marketplace</h1>
        <p className="text-sm text-muted-foreground">
          Publish courses, fun dives, and liveaboards for divers to discover in the app.
        </p>
      </div>
      </AnimatedItem>

      <AnimatedItem>
      <Card>
        <CardHeader>
          <CardTitle className="text-base">New listing</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-3">
          <div className="grid gap-3 sm:grid-cols-2">
            <div>
              <Label htmlFor="title">Title</Label>
              <Input id="title" value={title} onChange={(e) => setTitle(e.target.value)} />
            </div>
            <div>
              <Label htmlFor="type">Type</Label>
              <Input id="type" value={listingType} onChange={(e) => setListingType(e.target.value)} />
            </div>
          </div>
          <div>
            <Label htmlFor="desc">Description</Label>
            <Textarea id="desc" value={description} onChange={(e) => setDescription(e.target.value)} rows={3} />
          </div>
          <div className="grid gap-3 sm:grid-cols-2">
            <div>
              <Label htmlFor="price">Price (EUR)</Label>
              <Input id="price" type="number" value={price} onChange={(e) => setPrice(e.target.value)} />
            </div>
            <div>
              <Label htmlFor="region">Region</Label>
              <Input id="region" value={region} onChange={(e) => setRegion(e.target.value)} />
            </div>
          </div>
          <Button
            disabled={!title.trim() || description.length < 10 || createListing.isPending}
            onClick={() => {
              createListing.mutate(
                {
                  listing_type: listingType,
                  title: title.trim(),
                  description: description.trim(),
                  price_cents: Math.round(Number(price) * 100),
                  region: region.trim() || undefined,
                },
                {
                  onSuccess: () => {
                    setTitle("");
                    setDescription("");
                  },
                },
              );
            }}
          >
            Publish listing
          </Button>
          {createListing.isError ? (
            <p className="text-sm text-destructive">
              {(createListing.error as Error).message}
            </p>
          ) : null}
          {createListing.isSuccess ? (
            <p className="text-sm text-muted-foreground">Listing published.</p>
          ) : null}
        </CardContent>
      </Card>
      </AnimatedItem>

      <AnimatedItem>
      {isError ? (
        <EmptyState
          icon={Store}
          title="Couldn’t load listings"
          description="There was a problem fetching your marketplace listings."
          actionLabel="Retry"
          onAction={() => refetch()}
        />
      ) : !data?.length ? (
        <EmptyState
          icon={Store}
          title="No listings"
          description="Create your first marketplace offering."
        />
      ) : (
        <div className="grid gap-3">
          {data.map((item) => (
            <Card key={item.id} className="transition-all hover:shadow-md hover:border-ocean-500/40">
              <CardContent className="flex flex-wrap items-center justify-between gap-3 py-4">
                <div>
                  <p className="font-medium">{item.title}</p>
                  <p className="text-sm text-muted-foreground">
                    {item.listing_type} · {item.currency}{" "}
                    {(item.price_cents / 100).toFixed(0)}
                    {item.region ? ` · ${item.region}` : ""}
                  </p>
                </div>
                <Button
                  size="sm"
                  variant={item.is_active ? "outline" : "default"}
                  disabled={updateListing.isPending}
                  onClick={() =>
                    updateListing.mutate({ id: item.id, is_active: !item.is_active })
                  }
                >
                  {item.is_active ? "Deactivate" : "Activate"}
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
      </AnimatedItem>
    </AnimatedPage>
  );
}
