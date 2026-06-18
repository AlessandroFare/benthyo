import {
  BadRequestException,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { createHash } from 'crypto';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';

@Injectable()
export class SyncExtensionsService {
  constructor(private readonly supabase: SupabaseService) {}

  async queueInatPush(token: string, userId: string, sightingId: string) {
    const client = this.supabase.createClient(token);
    const sighting = assertNoError(
      await client
        .from('sightings')
        .select('id, user_id, verified_by, photo_urls')
        .eq('id', sightingId)
        .maybeSingle(),
    );
    if (!sighting || sighting.user_id !== userId) {
      throw new ForbiddenException('Sighting not found');
    }
    if (!sighting.verified_by && (sighting.photo_urls as string[])?.length === 0) {
      throw new ForbiddenException('Verified sighting or photo required for iNat push');
    }

    return assertNoError(
      await client
        .from('inaturalist_push_queue')
        .upsert(
          { sighting_id: sightingId, user_id: userId, status: 'pending' },
          { onConflict: 'sighting_id' },
        )
        .select('*')
        .single(),
    );
  }

  async pushGbifExport(token: string, userId: string) {
    const client = this.supabase.createClient(token);
    const profile = assertNoError(
      await client.from('users').select('gbif_export_opt_in').eq('id', userId).single(),
    );
    if (!profile?.gbif_export_opt_in) {
      throw new ForbiddenException('Enable GBIF export in settings first');
    }

    const sightings = assertNoError(
      await client
        .from('sightings')
        .select('id')
        .eq('user_id', userId)
        .not('verified_by', 'is', null)
        .is('gbif_exported_at', null),
    );

    const ids = (sightings ?? []).map((s) => s.id as string);
    if (ids.length > 0) {
      await client
        .from('sightings')
        .update({ gbif_exported_at: new Date().toISOString() })
        .in('id', ids);
    }

    return assertNoError(
      await client
        .from('gbif_export_batches')
        .insert({ user_id: userId, sighting_count: ids.length })
        .select('*')
        .single(),
    );
  }

  async registerPhotoFingerprint(
    token: string,
    userId: string,
    dto: { sighting_id: string; photo_url: string; sha256: string; species_id?: string },
  ) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client.from('sighting_photo_fingerprints').insert({
        sighting_id: dto.sighting_id,
        photo_url: dto.photo_url,
        sha256: dto.sha256,
        species_id: dto.species_id ?? null,
        user_id: userId,
      }),
    );
  }

  async searchByPhotoHash(sha256: string, userId?: string) {
    const client = this.supabase.anonClient();
    let query = client
      .from('sighting_photo_fingerprints')
      .select('*, sighting:sightings(id, observed_at), species:species(scientific_name, common_name)')
      .eq('sha256', sha256);
    if (userId) query = query.eq('user_id', userId);
    return assertNoError(await query.limit(10));
  }

  async registerClipEmbedding(
    token: string,
    userId: string,
    dto: {
      sighting_id: string;
      photo_url: string;
      sha256: string;
      embedding: number[];
      species_id?: string;
    },
  ) {
    if (dto.embedding.length !== 512) {
      throw new BadRequestException('CLIP embedding must be 512 dimensions');
    }
    const client = this.supabase.createClient(token);
    const vectorLiteral = `[${dto.embedding.join(',')}]`;

    const existing = assertNoError(
      await client
        .from('sighting_photo_fingerprints')
        .select('id')
        .eq('sha256', dto.sha256)
        .maybeSingle(),
    );

    if (existing) {
      return assertNoError(
        await client
          .from('sighting_photo_fingerprints')
          .update({
            clip_embedding: vectorLiteral,
            species_id: dto.species_id ?? null,
          })
          .eq('id', existing.id)
          .select('*')
          .single(),
      );
    }

    return assertNoError(
      await client.from('sighting_photo_fingerprints').insert({
        sighting_id: dto.sighting_id,
        photo_url: dto.photo_url,
        sha256: dto.sha256,
        species_id: dto.species_id ?? null,
        user_id: userId,
        clip_embedding: vectorLiteral,
      }).select('*').single(),
    );
  }

  async searchByClipEmbedding(embedding: number[], limit = 10) {
    if (embedding.length !== 512) {
      throw new BadRequestException('CLIP embedding must be 512 dimensions');
    }
    const client = this.supabase.anonClient();
    const vectorLiteral = `[${embedding.join(',')}]`;
    return assertNoError(
      await client.rpc('match_photo_embeddings', {
        query_embedding: vectorLiteral,
        match_limit: Math.min(limit, 50),
      }),
    );
  }

  static hashKey(raw: string): string {
    return createHash('sha256').update(raw).digest('hex');
  }
}
