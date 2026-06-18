import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api-client";

export type TripScheduleStatus =
  | "planned"
  | "confirmed"
  | "departed"
  | "completed"
  | "cancelled";

export interface RosterTrip {
  trip_id: string;
  trip_date: string;
  depart_at: string | null;
  site_name: string | null;
  boat_name: string | null;
  boat_capacity: number | null;
  guide_name: string | null;
  status: TripScheduleStatus;
  booked_count: number;
  checked_in_count: number;
}

/**
 * Today's roster for the active operator. Backed by the
 * operator_today_roster() RPC via the `/operators/me/roster` API route.
 * `date` is an optional YYYY-MM-DD override (defaults server-side to today).
 */
export function useTodayRoster(date?: string) {
  return useQuery({
    queryKey: ["roster", "today", date ?? "today"],
    queryFn: () =>
      api.get<RosterTrip[]>("/operators/me/roster", date ? { date } : undefined),
  });
}
