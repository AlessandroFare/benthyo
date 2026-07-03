import { useMemo, useState } from "react";
import { Anchor, CalendarDays, CheckCircle2, Clock, MapPin, Users } from "lucide-react";
import { useTodayRoster, type RosterTrip } from "@/hooks/useRoster";
import { AnimatedPage, AnimatedItem } from "@/components/shared/AnimatedPage";
import { Card, CardContent } from "@/components/ui/card";

const STATUS_STYLES: Record<RosterTrip["status"], { badge: string; border: string }> = {
  planned:   { badge: "bg-sky-500/12 text-sky-300 border border-sky-500/20",     border: "border-l-sky-400" },
  confirmed: { badge: "bg-blue-500/12 text-blue-300 border border-blue-500/20",  border: "border-l-blue-400" },
  departed:  { badge: "bg-amber-500/12 text-amber-300 border border-amber-500/20", border: "border-l-amber-400" },
  completed: { badge: "bg-emerald-500/12 text-emerald-300 border border-emerald-500/20", border: "border-l-emerald-400" },
  cancelled: { badge: "bg-rose-500/12 text-rose-400 border border-rose-500/20",  border: "border-l-rose-400" },
};

function formatTime(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
  });
}

function TripCard({ trip }: { trip: RosterTrip }) {
  const capacity = trip.boat_capacity ?? null;
  const overbooked = capacity != null && trip.booked_count > capacity;
  const capacityPct = capacity != null ? Math.min(100, (trip.booked_count / capacity) * 100) : null;
  const style = STATUS_STYLES[trip.status];

  return (
    <Card
      className={`overflow-hidden border-l-4 transition duration-200 hover:-translate-y-0.5 hover:shadow-lg ${style.border}`}
    >
      <CardContent className="p-5">
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <Clock className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
              <p className="text-lg font-bold tabular-nums text-foreground">
                {formatTime(trip.depart_at)}
              </p>
            </div>
            <p className="mt-1 flex items-center gap-1.5 text-sm text-muted-foreground">
              <MapPin className="h-3.5 w-3.5 shrink-0" />
              <span className="truncate">{trip.site_name ?? "Site TBD"}</span>
            </p>
          </div>
          <span
            className={`rounded-full px-2.5 py-1 text-[11px] font-semibold capitalize ${style.badge}`}
          >
            {trip.status}
          </span>
        </div>

        <div className="mt-4 grid grid-cols-3 gap-3 text-sm">
          <div className="flex items-center gap-2 text-muted-foreground">
            <Anchor className="h-4 w-4 shrink-0 text-ocean-400" />
            <span className="truncate text-xs">{trip.boat_name ?? "No boat"}</span>
          </div>
          <div className="flex items-center gap-2 text-muted-foreground">
            <Users className="h-4 w-4 shrink-0 text-ocean-400" />
            <span className={`text-xs font-medium ${overbooked ? "text-rose-400" : ""}`}>
              {capacity != null ? `${trip.booked_count}/${capacity}` : trip.booked_count}
            </span>
          </div>
          <div className="flex items-center gap-2 text-muted-foreground">
            <CheckCircle2 className="h-4 w-4 shrink-0 text-emerald-400" />
            <span className="text-xs">{trip.checked_in_count} in</span>
          </div>
        </div>

        {capacityPct !== null && (
          <div className="mt-3">
            <div className="h-1.5 w-full overflow-hidden rounded-full bg-border">
              <div
                className={`h-full rounded-full transition-all duration-500 ${
                  overbooked ? "bg-rose-400" : capacityPct >= 80 ? "bg-amber-400" : "bg-ocean-400"
                }`}
                style={{ width: `${capacityPct}%` }}
              />
            </div>
          </div>
        )}

        <p className="mt-3 text-xs text-muted-foreground">
          Guide: <span className="font-medium text-foreground/70">{trip.guide_name ?? "Unassigned"}</span>
        </p>
      </CardContent>
    </Card>
  );
}

export default function Today() {
  const [date, setDate] = useState<string>(
    () => new Date().toISOString().slice(0, 10),
  );
  const { data, isLoading, isError } = useTodayRoster(date);

  const totals = useMemo(() => {
    const trips = data ?? [];
    return {
      trips: trips.length,
      divers: trips.reduce((sum, t) => sum + t.booked_count, 0),
      checkedIn: trips.reduce((sum, t) => sum + t.checked_in_count, 0),
    };
  }, [data]);

  return (
    <AnimatedPage>
      <AnimatedItem>
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold text-foreground">
            <CalendarDays className="h-6 w-6 text-ocean-500" />
            Today
          </h1>
          <p className="text-sm text-muted-foreground">
            {totals.trips} trips · {totals.divers} divers booked ·{" "}
            {totals.checkedIn} checked in
          </p>
        </div>
        <input
          type="date"
          value={date}
          onChange={(e) => setDate(e.target.value)}
          className="rounded-xl border border-border bg-card px-3 py-2 text-sm text-foreground"
          aria-label="Roster date"
        />
      </header>
      </AnimatedItem>

      {isLoading && (
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {[0, 1, 2].map((i) => (
            <div
              key={i}
              className="h-40 animate-pulse rounded-2xl border border-border bg-card"
            />
          ))}
        </div>
      )}

      {isError && (
        <div className="rounded-2xl border border-rose-500/30 bg-rose-500/10 p-6 text-sm text-rose-300">
          Couldn’t load the roster. Check your connection and try again.
        </div>
      )}

      {!isLoading && !isError && (data?.length ?? 0) === 0 && (
        <div className="rounded-2xl border border-dashed border-border bg-card p-12 text-center">
          <CalendarDays className="mx-auto h-10 w-10 text-muted-foreground" />
          <p className="mt-3 font-medium text-foreground">No trips scheduled</p>
          <p className="text-sm text-muted-foreground">
            Nothing on the water for this date yet.
          </p>
        </div>
      )}

      {!isLoading && !isError && (data?.length ?? 0) > 0 && (
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {data!.map((trip) => (
            <TripCard key={trip.trip_id} trip={trip} />
          ))}
        </div>
      )}
    </AnimatedPage>
  );
}
