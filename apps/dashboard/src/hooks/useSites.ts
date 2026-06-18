import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "@/lib/api-client";
import type { OperatorSite } from "@/lib/types";
import { useOperator } from "./useOperator";

export function useSites() {
  const { data: operator } = useOperator();
  return useQuery({
    queryKey: ["sites", operator?.id],
    queryFn: () =>
      api.get<OperatorSite[]>(`/operators/${operator!.id}/sites`),
    enabled: Boolean(operator?.id),
  });
}

export function useAddSite() {
  const queryClient = useQueryClient();
  const { data: operator } = useOperator();
  return useMutation({
    mutationFn: (diveSiteId: string) =>
      api.post<OperatorSite>(`/operators/${operator!.id}/sites`, {
        dive_site_id: diveSiteId,
        is_primary: false,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["sites"] });
      queryClient.invalidateQueries({ queryKey: ["dashboard"] });
    },
  });
}

export function useRemoveSite() {
  const queryClient = useQueryClient();
  const { data: operator } = useOperator();
  return useMutation({
    mutationFn: (diveSiteId: string) =>
      api.delete<void>(`/operators/${operator!.id}/sites/${diveSiteId}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["sites"] });
      queryClient.invalidateQueries({ queryKey: ["dashboard"] });
    },
  });
}
