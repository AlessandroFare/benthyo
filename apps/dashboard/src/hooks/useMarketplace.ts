import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "@/lib/api-client";

export type MarketplaceListing = {
  id: string;
  listing_type: string;
  title: string;
  description: string;
  price_cents: number;
  currency: string;
  region: string | null;
  is_active: boolean;
  created_at: string;
};

export function useOperatorMarketplace() {
  return useQuery({
    queryKey: ["marketplace", "operator"],
    queryFn: () => api.get<MarketplaceListing[]>("/operators/me/marketplace"),
  });
}

export function useCreateMarketplaceListing() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: {
      listing_type: string;
      title: string;
      description: string;
      price_cents: number;
      region?: string;
    }) => api.post("/operators/me/marketplace", body),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["marketplace"] }),
  });
}

export function useUpdateMarketplaceListing() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({
      id,
      ...body
    }: {
      id: string;
      is_active?: boolean;
      title?: string;
      description?: string;
      price_cents?: number;
    }) => api.patch(`/operators/me/marketplace/${id}`, body),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["marketplace"] }),
  });
}
