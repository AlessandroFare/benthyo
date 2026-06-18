import { Injectable } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { DiveSite, Species } from '../database/database.types';
import { paginated, PaginatedResult } from '../common/dto/pagination.dto';
import { SearchHit, UnifiedSearchDto } from './dto/search.dto';

@Injectable()
export class SearchService {
  constructor(private readonly supabase: SupabaseService) {}

  async search(
    token: string | undefined,
    query: UnifiedSearchDto,
  ): Promise<PaginatedResult<SearchHit>> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    const type = query.type ?? 'all';
    const hits: SearchHit[] = [];

    if (type === 'all' || type === 'dive_sites') {
      const sites = await client
        .from('dive_sites')
        .select('id, name, slug, region, country_code')
        .textSearch('search_tsv', query.q, { type: 'websearch', config: 'simple' })
        .limit(query.limit);

      for (const site of (sites.data ?? []) as Pick<
        DiveSite,
        'id' | 'name' | 'slug' | 'region' | 'country_code'
      >[]) {
        hits.push({
          type: 'dive_site',
          id: site.id,
          title: site.name,
          subtitle: [site.region, site.country_code].filter(Boolean).join(', ') || null,
          slug: site.slug,
        });
      }
    }

    if (type === 'all' || type === 'species') {
      const species = await client
        .from('species')
        .select('id, scientific_name, common_name, image_url')
        .textSearch('search_tsv', query.q, { type: 'websearch', config: 'simple' })
        .limit(query.limit);

      for (const sp of (species.data ?? []) as Pick<
        Species,
        'id' | 'scientific_name' | 'common_name' | 'image_url'
      >[]) {
        hits.push({
          type: 'species',
          id: sp.id,
          title: sp.common_name ?? sp.scientific_name,
          subtitle: sp.common_name ? sp.scientific_name : null,
          image_url: sp.image_url,
        });
      }
    }

    hits.sort((a, b) => a.title.localeCompare(b.title));

    const start = query.offset;
    const pageHits = hits.slice(start, start + query.limit);

    return paginated(pageHits, hits.length, query.page, query.limit);
  }
}
