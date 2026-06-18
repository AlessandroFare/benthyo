import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api-client";
import type {
  ActivityItem,
  DashboardCharts,
  DashboardKpis,
} from "@/lib/types";

export function useDashboardKpis() {
  return useQuery({
    queryKey: ["dashboard", "kpis"],
    queryFn: () => api.get<DashboardKpis>("/operators/me/dashboard/kpis"),
  });
}

export function useDashboardCharts() {
  return useQuery({
    queryKey: ["dashboard", "charts"],
    queryFn: () => api.get<DashboardCharts>("/operators/me/dashboard/charts"),
  });
}

export function useRecentActivity() {
  return useQuery({
    queryKey: ["dashboard", "activity"],
    queryFn: () => api.get<ActivityItem[]>("/operators/me/dashboard/activity"),
  });
}
