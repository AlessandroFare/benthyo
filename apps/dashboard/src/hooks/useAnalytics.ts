import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api-client";
import type { AnalyticsData } from "@/lib/types";

export function useAnalytics() {
  return useQuery({
    queryKey: ["analytics"],
    queryFn: () => api.get<AnalyticsData>("/operators/me/analytics"),
  });
}
