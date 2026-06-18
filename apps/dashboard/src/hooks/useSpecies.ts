import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api-client";
import type { Paginated, Species, SpeciesDetail, SpeciesRanked } from "@/lib/types";
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

type SpeciesApiDetail = Species & {
  top_sites: Array<{
    dive_site_id: string;
    name: string;
    sighting_count: number;
  }>;
};

export function useSpecies(page = 1, search = "") {
  const { data: operator } = useOperator();
  return useQuery({
    queryKey: ["species", operator?.id, page, search],
    queryFn: async (): Promise<Paginated<SpeciesRanked>> => {
      const result = await api.get<ApiPaginated<SpeciesRanked>>("/operators/me/species", {
        page,
        limit: 20,
        q: search || undefined,
      });
      return toPaginated(result);
    },
    enabled: Boolean(operator?.id),
  });
}

export function useSpeciesDetail(id: string | undefined) {
  return useQuery({
    queryKey: ["species", "detail", id],
    queryFn: async (): Promise<SpeciesDetail> => {
      const raw = await api.get<SpeciesApiDetail>(`/species/${id}`);
      const topSites = (raw.top_sites ?? []).map((site) => ({
        id: site.dive_site_id,
        name: site.name,
        count: site.sighting_count,
      }));
      const sightingCount = topSites.reduce((sum, site) => sum + site.count, 0);
      return {
        ...raw,
        sighting_count: sightingCount,
        site_count: topSites.length,
        avg_depth_m: null,
        monthly_trend: [],
        top_sites: topSites,
      };
    },
    enabled: Boolean(id),
  });
}
