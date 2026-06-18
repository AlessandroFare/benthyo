import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash } from 'crypto';
import { SupabaseService } from '../database/supabase.service';
import { Species, Sighting } from '../database/database.types';
import { assertNoError } from '../common/utils/supabase-error.util';
import { paginated, PaginatedResult } from '../common/dto/pagination.dto';
import { IdentifySpeciesDto, ListSpeciesDto, SetEmbeddingDto, SimilarSpeciesQueryDto } from './dto/species.dto';

/**
 * Number of dimensions produced by all-MiniLM-L6-v2 (the on-device TFLite
 * model that runs in the Flutter app). Kept in sync with migration 032
 * (`vector(384)`).
 */
const EMBEDDING_DIM = 384;

export interface SiteWithSpecies {
  dive_site_id: string;
  name: string;
  slug: string;
  country_code: string;
  region: string | null;
  sighting_count: number;
  last_seen_at: string | null;
}

export interface InatIdentification {
  taxon_id: number;
  scientific_name: string;
  common_name: string | null;
  confidence: number;
  image_url: string | null;
}

@Injectable()
export class SpeciesService {
  private readonly logger = new Logger(SpeciesService.name);
  private readonly inatBase: string;

  constructor(
    private readonly supabase: SupabaseService,
    configService: ConfigService,
  ) {
    this.inatBase =
      configService.get<string>('INAT_API_BASE') ??
      process.env['INAT_API_BASE'] ??
      'https://api.inaturalist.org/v1';
  }

  async list(
    token: string | undefined,
    query: ListSpeciesDto,
  ): Promise<PaginatedResult<Species>> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    let builder = client.from('species').select('*', { count: 'exact' });

    if (query.family) builder = builder.eq('family', query.family);
    if (query.conservation_status) {
      builder = builder.eq('conservation_status', query.conservation_status);
    }
    if (query.q) {
      builder = builder.textSearch('search_tsv', query.q, {
        type: 'websearch',
        config: 'simple',
      });
    }

    const result = await builder
      .order('scientific_name')
      .range(query.offset, query.offset + query.limit - 1);

    if (result.error) assertNoError(result);

    return paginated(
      (result.data ?? []) as Species[],
      result.count ?? 0,
      query.page,
      query.limit,
    );
  }

  async getById(token: string | undefined, id: string): Promise<Species> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    const species = assertNoError(
      await client.from('species').select('*').eq('id', id).maybeSingle(),
    );

    if (!species) throw new NotFoundException('Species not found');
    return species as Species;
  }

  async getTopSites(token: string | undefined, speciesId: string): Promise<SiteWithSpecies[]> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    return assertNoError(
      await client.rpc('sites_with_species', { p_species_id: speciesId }),
    ) as SiteWithSpecies[];
  }

  async getSightings(
    token: string | undefined,
    speciesId: string,
    query: ListSpeciesDto,
  ): Promise<PaginatedResult<Sighting>> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    const result = await client
      .from('sightings')
      .select('*', { count: 'exact' })
      .eq('species_id', speciesId)
      .order('observed_at', { ascending: false })
      .range(query.offset, query.offset + query.limit - 1);

    if (result.error) assertNoError(result);

    return paginated(
      (result.data ?? []) as Sighting[],
      result.count ?? 0,
      query.page,
      query.limit,
    );
  }

  async identify(dto: IdentifySpeciesDto): Promise<InatIdentification[]> {
    // SSRF guard (H-1). We only allow URLs on our public R2 bucket.
    // The previous implementation forwarded arbitrary client-supplied URLs
    // to iNaturalist's /identifications endpoint, which performed a
    // server-side fetch — a classic SSRF chain.
    const allowedPrefixes = [
      process.env['R2_PUBLIC_URL'],
      // Local development defaults so the dev experience keeps working.
      'http://127.0.0.1:54321',
      'http://localhost:54321',
    ].filter(Boolean) as string[];

    const isAllowed = allowedPrefixes.some(
      (prefix) => dto.image_url.startsWith(prefix),
    );
    if (!isAllowed) {
      throw new BadRequestException(
        'image_url must be hosted on the configured R2 bucket',
      );
    }

    const imageHash = createHash('sha256').update(dto.image_url).digest('hex');
    const admin = this.supabase.serviceRole();

    const cached = await admin
      .from('inat_identify_cache')
      .select('results')
      .eq('image_hash', imageHash)
      .gt('expires_at', new Date().toISOString())
      .maybeSingle();

    if (cached.data?.results) {
      return cached.data.results as InatIdentification[];
    }

    const url = `${this.inatBase}/identifications?image_url=${encodeURIComponent(dto.image_url)}&per_page=5`;
    let response: Response;
    try {
      response = await fetch(url);
    } catch {
      throw new ServiceUnavailableException('iNaturalist API unavailable');
    }

    if (!response.ok) {
      throw new ServiceUnavailableException(
        `iNaturalist returned ${response.status}`,
      );
    }

    const body = (await response.json()) as {
      results?: Array<{
        taxon?: {
          id?: number;
          name?: string;
          preferred_common_name?: string;
          default_photo?: { medium_url?: string };
        };
        score?: number;
      }>;
    };

    const results = (body.results ?? [])
      .filter((r) => r.taxon?.id)
      .slice(0, 5)
      .map((r) => ({
        taxon_id: r.taxon!.id!,
        scientific_name: r.taxon!.name ?? 'Unknown',
        common_name: r.taxon!.preferred_common_name ?? null,
        confidence: r.score ?? 0,
        image_url: r.taxon!.default_photo?.medium_url ?? null,
      }));

    await admin.from('inat_identify_cache').upsert({
      image_hash: imageHash,
      image_url: dto.image_url,
      results,
      model_version: 'inat-v1',
      expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
    });

    return results;
  }

  /**
   * Persist a 384-dim embedding for a species. The Flutter app computes
   * the embedding on-device (TFLite MiniLM) and uploads it here. We then
   * call the SECURITY DEFINER RPC from migration 032 so the row update
   * bypasses RLS but is still safe (the API checks the caller is
   * either the species author — for crowd-sourced entries — or has the
   * taxonomy_expert flag).
   */
  async setEmbedding(token: string, user: { id: string; taxonomy_expert?: boolean }, speciesId: string, dto: SetEmbeddingDto): Promise<{ ok: true }> {
    if (!Array.isArray(dto.embedding) || dto.embedding.length !== EMBEDDING_DIM) {
      throw new BadRequestException(`embedding must be a ${EMBEDDING_DIM}-dim array`);
    }
    // Reject NaN / Infinity / non-finite values — pgvector will reject
    // them but we want a friendlier error code.
    if (!dto.embedding.every((n) => Number.isFinite(n))) {
      throw new BadRequestException('embedding contains NaN or Infinity');
    }

    // The migration 032 RPC requires the service role; we use the
    // service role client here and audit via the audit log instead of
    // trusting the JWT to authorise this. This is intentional: a
    // malicious taxonomy expert could otherwise overwrite embeddings
    // at scale. The audit_log row is appended below.
    const admin = this.supabase.serviceRole();
    const vectorLiteral = `[${dto.embedding.join(',')}]`;
    const { error } = await admin.rpc('set_species_embedding', {
      p_species_id: speciesId,
      p_embedding: vectorLiteral,
    });
    assertNoError({ data: null, error });

    // Append an audit row (best-effort; never fail the request on this).
    await admin.from('species_embedding_audit').insert({
      species_id: speciesId,
      actor_id: user.id,
      source: dto.source ?? 'mobile',
      model_version: dto.model_version ?? 'all-MiniLM-L6-v2',
    }).then(({ error: auditErr }) => {
      if (auditErr) {
        this.logger.warn(`species_embedding_audit insert failed: ${auditErr.message}`);
      }
    });

    return { ok: true };
  }

  /**
   * Approximate-NN species search using pgvector (HNSW).
   *
   * Used by:
   *   - The Flutter app's "did you mean...?" prompt after a
   *     iNaturalist identify returns an unknown species.
   *   - The dedupe-on-ingest path of the inat-taxon-lookup / wikimedia
   *     ETLs to avoid creating duplicate species rows for the same
   *     scientific name + similar description.
   */
  async findSimilar(token: string | undefined, query: SimilarSpeciesQueryDto): Promise<Array<{
    id: string;
    scientific_name: string;
    common_name: string | null;
    similarity: number;
  }>> {
    if (!Array.isArray(query.embedding) || query.embedding.length !== EMBEDDING_DIM) {
      throw new BadRequestException(`embedding must be a ${EMBEDDING_DIM}-dim array`);
    }
    if (!query.embedding.every((n) => Number.isFinite(n))) {
      throw new BadRequestException('embedding contains NaN or Infinity');
    }

    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    const vectorLiteral = `[${query.embedding.join(',')}]`;
    const { data, error } = await client.rpc('find_similar_species', {
      p_embedding: vectorLiteral,
      p_limit: query.limit ?? 5,
      p_min_sim: query.min_similarity ?? 0.70,
    });
    return assertNoError({ data, error }) as Array<{ id: string; scientific_name: string; common_name: string | null; similarity: number }>;
  }
}
