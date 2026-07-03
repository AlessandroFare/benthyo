import { useState } from "react";
import { useCheckinRentalGear, useCreateRentalGear, useRentalGear } from "@/hooks/useRentalGear";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { TableSkeleton } from "@/components/shared/LoadingSkeleton";
import { AnimatedPage, AnimatedItem } from "@/components/shared/AnimatedPage";
import { EmptyState } from "@/components/shared/EmptyState";
import { Package } from "lucide-react";

export function RentalGearPage() {
  const { data, isLoading, isError, refetch } = useRentalGear();
  const createGear = useCreateRentalGear();
  const checkin = useCheckinRentalGear();
  const [label, setLabel] = useState("");
  const [gearType, setGearType] = useState("bcd");

  if (isLoading) return <TableSkeleton rows={6} />;

  return (
    <AnimatedPage>
      <AnimatedItem>
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Rental gear</h1>
        <p className="text-sm text-muted-foreground">
          Register inventory with QR codes for checkout tracking.
        </p>
      </div>
      </AnimatedItem>

      <AnimatedItem>
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Add gear</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-3 sm:grid-cols-3">
          <div>
            <Label htmlFor="label">Label</Label>
            <Input id="label" value={label} onChange={(e) => setLabel(e.target.value)} />
          </div>
          <div>
            <Label htmlFor="type">Type</Label>
            <Input id="type" value={gearType} onChange={(e) => setGearType(e.target.value)} />
          </div>
          <div className="flex items-end">
            <Button
              disabled={!label.trim() || createGear.isPending}
              onClick={() => {
                createGear.mutate({ gear_type: gearType, label: label.trim() });
                setLabel("");
              }}
            >
              Register
            </Button>
          </div>
        </CardContent>
      </Card>
      </AnimatedItem>

      <AnimatedItem>
      {isError ? (
        <EmptyState
          icon={Package}
          title="Couldn’t load rental gear"
          description="There was a problem fetching your rental inventory."
          actionLabel="Retry"
          onAction={() => refetch()}
        />
      ) : !data?.length ? (
        <EmptyState
          icon={Package}
          title="No rental gear"
          description="Register your first BCD or regulator."
        />
      ) : (
        <div className="grid gap-3">
          {data.map((item) => (
            <Card key={item.id} className="transition-all hover:shadow-md hover:border-ocean-500/40">
              <CardContent className="flex flex-wrap items-center justify-between gap-3 py-4">
                <div>
                  <p className="font-medium">{item.label}</p>
                  <p className="text-sm text-muted-foreground">
                    {item.gear_type} · QR {item.qr_code} · {item.dives_since_service} dives since
                    service
                  </p>
                  {item.checked_out_to && (
                    <p className="text-xs text-amber-600">Checked out</p>
                  )}
                </div>
                {item.checked_out_to && (
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={checkin.isPending}
                    onClick={() => checkin.mutate(item.qr_code)}
                  >
                    Check in
                  </Button>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      )}
      </AnimatedItem>
    </AnimatedPage>
  );
}
