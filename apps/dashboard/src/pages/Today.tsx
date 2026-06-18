import { useMemo, useState } from "react";
import { Anchor, CalendarDays, CheckCircle2, MapPin, Users } from "lucide-react";
import { useTodayRoster, type RosterTrip } from "@/hooks/useRoster";

const STATUS_STYLES: Record<RosterTrip["status"], string> = {
  planned: "bg-slate-100 text-slate-700",
  confirmed: "bg-blue-100 text-blue-700",
  departed: "bg-amber-100 text-amber-700",
  completed: "bg-emerald-100 text-emerald-700",
  cancelled: "bg-rose-100 text-rose-700",
};

function formatTime(iso: string | null): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
  });
}

function TripCard({ trip }: { trip: RosterTrip }) {
  const capacityLabel =
    trip.boat_capacity != null
      ? `${trip.booked_count}/${trip.boat_capacity}`
      : `${trip.booked_count}`;
  const overbooked =
    trip.boat_capacity != null && trip.booked_count > trip.boat_capacity;

  return (
    <div className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm transition hover:shadow-md">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <p className="text-lg font-semibold text-slate-900">
            {formatTime(trip.depart_at)}
          </p>
          <p className="flex items-center gap-1.5 text-sm text-slate-500">
            <MapPin className="h-4 w-4 shrink-0" />
            <span className="truncate">{trip.site_name ?? "Site TBD"}</span>
          </p>
        </div>
        <span
          className={`rounded-full px-3 py-1 text-xs font-medium capitalize ${STATUS_STYLES[trip.status]}`}
        >
          {trip.status}
        </span>
      </div>

      <div className="mt-4 grid grid-cols-3 gap-3 text-sm">
        <div className="flex items-center gap-2 text-slate-600">
          <Anchor className="h-4 w-4 shrink-0 text-ocean-500" />
          <span className="truncate">{trip.boat_name ?? "No boat"}</span>
        </div>
        <div className="flex items-center gap-2 text-slate-600">
          <Users className="h-4 w-4 shrink-0 text-ocean-500" />
          <span className={overbooked ? "font-semibold text-rose-600" : ""}>
            {capacityLabel}
          </span>
        </div>
        <div className="flex items-center gap-2 text-slate-600">
          <CheckCircle2 className="h-4 w-4 shrink-0 text-emerald-500" />
          <span>{trip.checked_in_count} in</span>
        </div>
      </div>

      <p className="mt-3 text-xs text-slate-400">
        Guide: {trip.guide_name ?? "Unassigned"}
      </p>
    </div>
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
    <div className="space-y-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold text-slate-900">
            <CalendarDays className="h-6 w-6 text-ocean-500" />
            Today
          </h1>
          <p className="text-sm text-slate-500">
            {totals.trips} trips · {totals.divers} divers booked ·{" "}
            {totals.checkedIn} checked in
          </p>
        </div>
        <input
          type="date"
          value={date}
          onChange={(e) => setDate(e.target.value)}
          className="rounded-xl border border-slate-300 px-3 py-2 text-sm"
          aria-label="Roster date"
        />
      </header>

      {isLoading && (
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {[0, 1, 2].map((i) => (
            <div
              key={i}
              className="h-40 animate-pulse rounded-2xl border border-slate-200 bg-slate-50"
            />
          ))}
        </div>
      )}

      {isError && (
        <div className="rounded-2xl border border-rose-200 bg-rose-50 p-6 text-sm text-rose-700">
          Couldn’t load the roster. Check your connection and try again.
        </div>
      )}

      {!isLoading && !isError && (data?.length ?? 0) === 0 && (
        <div className="rounded-2xl border border-dashed border-slate-300 bg-white p-12 text-center">
          <CalendarDays className="mx-auto h-10 w-10 text-slate-300" />
          <p className="mt-3 font-medium text-slate-700">No trips scheduled</p>
          <p className="text-sm text-slate-500">
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
    </div>
  );
}
