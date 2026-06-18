import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "@/lib/api-client";

export type CorrectionRow = {
  id: string;
  reason: string;
  status: string;
  created_at: string;
  reporter: { username: string; full_name: string | null } | null;
  sighting: { id: string; species_id: string; user_id: string } | null;
  proposed: { scientific_name: string; common_name: string | null } | null;
};

export function useExpertCorrectionQueue() {
  return useQuery({
    queryKey: ["corrections", "expert-queue"],
    queryFn: () => api.get<CorrectionRow[]>("/corrections/expert/queue"),
  });
}

export function useExpertResolveCorrection() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({
      id,
      action,
    }: {
      id: string;
      action: "accept" | "reject";
    }) => api.post(`/corrections/${id}/expert-resolve`, { action }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["corrections"] }),
  });
}
