import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "@/lib/api-client";
import type { Operator, SettingsData, TeamMember } from "@/lib/types";
import { useOperator } from "./useOperator";

export function useSettings() {
  const { data: operator } = useOperator();
  return useQuery({
    queryKey: ["settings", operator?.id],
    queryFn: async (): Promise<SettingsData> => {
      const [op, team] = await Promise.all([
        api.get<Operator & { role: string }>("/operators/me"),
        api.get<TeamMember[]>(`/operators/${operator!.id}/members`),
      ]);
      return {
        operator: op,
        team,
        subscription: {
          tier: op.subscription_tier,
          status: op.subscription_status,
          current_period_end: null,
          sites_limit: op.subscription_tier === "pro" ? 100 : 10,
          team_limit: op.subscription_tier === "pro" ? 20 : 3,
          features: [],
        },
      };
    },
    enabled: Boolean(operator?.id),
  });
}

export function useUpdateOperator() {
  const queryClient = useQueryClient();
  const { data: operator } = useOperator();
  return useMutation({
    mutationFn: (data: Partial<Operator>) =>
      api.patch<Operator>(`/operators/${operator!.id}`, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["settings"] });
      queryClient.invalidateQueries({ queryKey: ["operators", "me"] });
    },
  });
}

export function useInviteTeamMember() {
  const queryClient = useQueryClient();
  const { data: operator } = useOperator();
  return useMutation({
    mutationFn: (data: { user_id: string; role: TeamMember["role"] }) =>
      api.post<TeamMember>(`/operators/${operator!.id}/members`, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["settings"] });
    },
  });
}

export function useExportCsv() {
  return useMutation({
    mutationFn: async (_type?: "customers" | "sightings" | "dives") => {
      const activity = await api.get<Array<{ occurred_at: string; description: string }>>(
        "/operators/me/dashboard/activity",
      );
      const csv = ["date,user", ...activity.map((r) => `${r.occurred_at},${r.description}`)].join(
        "\n",
      );
      const blob = new Blob([csv], { type: "text/csv" });
      return { download_url: URL.createObjectURL(blob) };
    },
  });
}
