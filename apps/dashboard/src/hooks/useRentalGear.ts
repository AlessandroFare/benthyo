import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "@/lib/api-client";

export type RentalGearRow = {
  id: string;
  label: string;
  gear_type: string;
  serial_number: string | null;
  qr_code: string;
  dives_since_service: number;
  checked_out_to: string | null;
  checked_out_at: string | null;
};

export function useRentalGear() {
  return useQuery({
    queryKey: ["rental-gear"],
    queryFn: () => api.get<RentalGearRow[]>("/operators/me/rental-gear"),
  });
}

export function useCreateRentalGear() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: { gear_type: string; label: string; serial_number?: string }) =>
      api.post<RentalGearRow>("/operators/me/rental-gear", body),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["rental-gear"] }),
  });
}

export function useCheckinRentalGear() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (qrCode: string) =>
      api.post(`/operators/me/rental-gear/${qrCode}/checkin`),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["rental-gear"] }),
  });
}
