import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api-client";
import type { Operator } from "@/lib/types";

export function useOperator() {
  return useQuery({
    queryKey: ["operators", "me"],
    queryFn: () => api.get<Operator & { role: string }>("/operators/me"),
    staleTime: 5 * 60_000,
  });
}
