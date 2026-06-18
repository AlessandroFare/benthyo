import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api-client";
import type { Customer, CustomerDetail, Paginated } from "@/lib/types";
import { useOperator } from "./useOperator";

type ApiPaginated<T> = {
  data: T[];
  total: number;
  page: number;
  limit: number;
};

function toPaginated<T>(result: ApiPaginated<T>): Paginated<T> {
  return {
    data: result.data,
    total: result.total,
    page: result.page,
    page_size: result.limit,
  };
}

export function useCustomers(page = 1, search = "") {
  const { data: operator } = useOperator();
  return useQuery({
    queryKey: ["customers", operator?.id, page, search],
    queryFn: async (): Promise<Paginated<Customer>> => {
      const result = await api.get<ApiPaginated<Customer>>("/operators/me/customers", {
        page,
        limit: 20,
        q: search || undefined,
      });
      return toPaginated(result);
    },
    enabled: Boolean(operator?.id),
  });
}

export function useCustomer(id: string | undefined) {
  const { data: operator } = useOperator();
  return useQuery({
    queryKey: ["customers", "detail", operator?.id, id],
    queryFn: async (): Promise<CustomerDetail> => {
      const result = await api.get<ApiPaginated<Customer>>("/operators/me/customers", {
        page: 1,
        limit: 100,
      });
      const customer = result.data.find((row) => row.id === id);
      if (!customer) {
        throw new Error("Customer not found");
      }
      return {
        ...customer,
        recent_dives: [],
        species_seen: [],
      };
    },
    enabled: Boolean(operator?.id && id),
  });
}
