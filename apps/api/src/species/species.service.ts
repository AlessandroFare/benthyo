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
import { AiVisionService, AiVisionResult } from './ai-vision.service';

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

/**
 * Rich response for the AI-assisted photo identification endpoint. Combines
 * the AI vision proposal, iNaturalist's vision candidates, and the reconciled
 * catalog species (which may have been created on the fly).
 */
export interface AiIdentifyResult {
  /** The AI vision proposal (Groq), or null when disabled/unsure. */
  ai: AiVisionResult | null;
  /** Catalog species matched to the identification (best first). */
  matches: Species[];
  /** Raw iNaturalist vision candidates (kept for transparency/fallback). */
  inat: InatIdentification[];
  /** True when we created a new catalog species from the AI result. */
  created: boolean;
}

@Injectable()
export class SpeciesService {
  private readonly logger = new Logger(SpeciesService.name);
  private readonly inatBase: string;

  constructor(
    private readonly supabase: SupabaseService,
    private readonly aiVision: AiVisionService,
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
   * AI-assisted photo identification.
   *
   * Pipeline:
   *   1. Run iNaturalist vision (existing, cached) AND Groq vision in parallel.
   *      iNat is a purpose-built species classifier; Groq adds robust common
   *      names (it/en/es) + reasoning and covers cases iNat misses.
   *   2. Reconcile both signals into an ordered list of candidate scientific
   *      names and match them against our catalog (scientific + common names).
   *   3. If the confident AI species is NOT yet in the catalog, create a
   *      minimal species row on the fly (metadata.source = 'ai_identify',
   *      needs_enrichment = true) so future searches find it and the ETLs
   *      (iNat/WoRMS) can enrich it later. Then it appears in `matches`.
   *
   * Never throws on AI/iNat provider errors — always returns the best result
   * it can assemble so the diver still gets an answer.
   */
  async identifyAi(dto: IdentifySpeciesDto): Promise<AiIdentifyResult> {
    const [inatSettled, aiSettled] = await Promise.allSettled([
      this.identify(dto),
      this.aiVision.identify(dto.image_url),
    ]);

    const inat: InatIdentification[] =
      inatSettled.status === 'fulfilled' ? inatSettled.value : [];
    const ai: AiVisionResult | null =
      aiSettled.status === 'fulfilled' ? aiSettled.value : null;

    if (inatSettled.status === 'rejected') {
      this.logger.warn(
        `iNat identify failed during AI flow: ${String(inatSettled.reason)}`,
      );
    }

    // Build an ordered, de-duplicated list of candidate scientific names.
    // AI proposal first (it carries the richest metadata), then iNat by score.
    const candidateNames: string[] = [];
    const pushName = (name: string | null | undefined) => {
      const clean = name?.trim();
      if (clean && !candidateNames.some((n) => n.toLowerCase() === clean.toLowerCase())) {
        candidateNames.push(clean);
      }
    };
    if (ai?.scientific_name) pushName(ai.scientific_name);
    for (const hit of inat) pushName(hit.scientific_name);

    // Collect common names the AI proposed so we can also match those.
    const commonNames = [ai?.common_name, ai?.common_name_it, ai?.common_name_es]
      .map((n) => n?.trim())
      .filter((n): n is string => !!n);

    let matches = await this.matchCatalog(candidateNames, commonNames);

    // On-the-fly creation: the confident AI species is not in the catalog yet.
    let created = false;
    const AI_CREATE_THRESHOLD = 0.55;
    if (
      ai?.scientific_name &&
      ai.is_marine &&
      ai.confidence >= AI_CREATE_THRESHOLD &&
      !matches.some(
        (m) =>
          m.scientific_name.toLowerCase() ===
          ai.scientific_name!.toLowerCase(),
      )
    ) {
      const createdRow = await this.createSpeciesFromAi(ai);
      if (createdRow) {
        matches = [createdRow, ...matches];
        created = true;
      }
    }

    return { ai, matches, inat, created };
  }

  /**
   * Find catalog species matching any of the candidate scientific names
   * (exact or genus-prefix) or any of the AI-proposed common names.
   */
  private async matchCatalog(
    scientificNames: string[],
    commonNames: string[],
  ): Promise<Species[]> {
    if (scientificNames.length === 0 && commonNames.length === 0) return [];

    const admin = this.supabase.serviceRole();
    const ors: string[] = [];

    for (const name of scientificNames) {
      const safe = this.sanitiseForOr(name);
      if (!safe) continue;
      // Exact scientific name OR genus prefix (e.g. "Amphiprion%").
      ors.push(`scientific_name.ilike.${safe}`);
      const genus = safe.split(' ')[0];
      if (genus && genus !== safe) ors.push(`scientific_name.ilike.${genus} %`);
    }
    for (const name of commonNames) {
      const safe = this.sanitiseForOr(name);
      if (!safe) continue;
      ors.push(`common_name.ilike.%${safe}%`);
      ors.push(`common_name_it.ilike.%${safe}%`);
      ors.push(`common_name_es.ilike.%${safe}%`);
    }
    if (ors.length === 0) return [];

    const { data, error } = await admin
      .from('species')
      .select('*')
      .or(ors.join(','))
      .limit(10);

    if (error) {
      this.logger.warn(`matchCatalog query failed: ${error.message}`);
      return [];
    }

    const rows = (data ?? []) as Species[];
    // Order results by candidate priority: exact scientific-name matches first.
    const order = new Map(
      scientificNames.map((n, i) => [n.toLowerCase(), i]),
    );
    return rows.sort((a, b) => {
      const ra = order.get(a.scientific_name.toLowerCase()) ?? 999;
      const rb = order.get(b.scientific_name.toLowerCase()) ?? 999;
      return ra - rb;
    });
  }

  /**
   * Create a minimal catalog species from an AI vision result. Idempotent:
   * upserts on scientific_name so concurrent identifications don't duplicate.
   * The row is intentionally sparse — the ETLs (iNat/WoRMS) enrich it later.
   */
  private async createSpeciesFromAi(ai: AiVisionResult): Promise<Species | null> {
    if (!ai.scientific_name) return null;
    const admin = this.supabase.serviceRole();

    const row = {
      scientific_name: ai.scientific_name,
      common_name: ai.common_name,
      common_name_it: ai.common_name_it,
      common_name_es: ai.common_name_es,
      family: ai.family,
      genus: ai.genus ?? ai.scientific_name.split(' ')[0],
      metadata: {
        source: 'ai_identify',
        ai_model: ai.source,
        ai_confidence: ai.confidence,
        needs_enrichment: true,
      },
    };

    const { data, error } = await admin
      .from('species')
      .upsert(row, { onConflict: 'scientific_name' })
      .select('*')
      .maybeSingle();

    if (error) {
      this.logger.warn(
        `createSpeciesFromAi failed for ${ai.scientific_name}: ${error.message}`,
      );
      return null;
    }
    return (data as Species) ?? null;
  }

  /**
   * Strip characters that are significant in PostgREST `.or()` filter
   * grammar (commas, parentheses) to avoid breaking the query or injecting
   * extra conditions. Percent/underscore are left intact (callers add their
   * own wildcards deliberately).
   */
  private sanitiseForOr(value: string): string | null {
    const cleaned = value.replace(/[(),]/g, ' ').trim();
    return cleaned.length ? cleaned : null;
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
