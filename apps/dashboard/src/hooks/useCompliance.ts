import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "@/lib/api-client";
import { useOperator } from "@/hooks/useOperator";

export function useOperatorWaiver() {
  const { data: operator } = useOperator();
  return useQuery({
    queryKey: ["waiver", operator?.slug],
    queryFn: () =>
      api.get<{ operator: { name: string; slug: string }; waiver: { title: string; body: string } | null }>(
        `/waivers/operator/${operator!.slug}/manage`,
      ),
    enabled: Boolean(operator?.slug),
  });
}

export function useUpsertWaiver() {
  const { data: operator } = useOperator();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: { title: string; body: string }) =>
      api.put(`/waivers/operator/${operator!.id}`, body),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["waiver"] }),
  });
}

export function usePaymentLinks() {
  return useQuery({
    queryKey: ["payment-links"],
    queryFn: () =>
      api.get<
        Array<{
          id: string;
          description: string;
          amount_cents: number;
          currency: string;
          payment_url: string;
          created_at: string;
        }>
      >("/operators/me/payment-links"),
  });
}

export function useCreatePaymentLink() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: {
      amount_cents: number;
      description: string;
      payment_url: string;
      customer_email?: string;
    }) => api.post("/operators/me/payment-links", body),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["payment-links"] }),
  });
}
