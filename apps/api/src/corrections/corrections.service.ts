import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';
import { SuggestCorrectionDto } from './dto/correction.dto';

@Injectable()
export class CorrectionsService {
  constructor(private readonly supabase: SupabaseService) {}

  async suggest(token: string, userId: string, dto: SuggestCorrectionDto) {
    const client = this.supabase.createClient(token);

    const sighting = assertNoError(
      await client
        .from('sightings')
        .select('id, user_id, species_id')
        .eq('id', dto.sighting_id)
        .maybeSingle(),
    );

    if (!sighting) throw new NotFoundException('Sighting not found');
    if (sighting.user_id === userId) {
      throw new ForbiddenException('Cannot suggest correction on your own sighting');
    }

    return assertNoError(
      await client
        .from('sighting_corrections')
        .insert({
          sighting_id: dto.sighting_id,
          reporter_id: userId,
          proposed_species_id: dto.proposed_species_id,
          reason: dto.reason,
        })
        .select('*')
        .single(),
    );
  }

  async accept(token: string, userId: string, correctionId: string) {
    const client = this.supabase.createClient(token);

    const correction = assertNoError(
      await client
        .from('sighting_corrections')
        .select('*, sighting:sightings(id, user_id, species_id, correction_log)')
        .eq('id', correctionId)
        .maybeSingle(),
    );

    if (!correction) throw new NotFoundException('Correction not found');

    const sighting = correction.sighting as {
      id: string;
      user_id: string;
      species_id: string;
      correction_log: unknown[];
    };

    if (sighting.user_id !== userId) {
      throw new ForbiddenException('Only the sighting owner can accept');
    }

    const logEntry = {
      from_species_id: sighting.species_id,
      to_species_id: correction.proposed_species_id,
      by: userId,
      at: new Date().toISOString(),
      reason: correction.reason,
    };

    const updatedLog = [...(sighting.correction_log ?? []), logEntry];

    await client
      .from('sightings')
      .update({
        species_id: correction.proposed_species_id,
        correction_log: updatedLog,
        updated_at: new Date().toISOString(),
      })
      .eq('id', sighting.id);

    return assertNoError(
      await client
        .from('sighting_corrections')
        .update({
          status: 'accepted',
          resolver_id: userId,
          resolved_at: new Date().toISOString(),
        })
        .eq('id', correctionId)
        .select('*')
        .single(),
    );
  }

  async listForSighting(token: string | undefined, sightingId: string) {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    return assertNoError(
      await client
        .from('sighting_corrections')
        .select('*, reporter:users!sighting_corrections_reporter_id_fkey(username, full_name)')
        .eq('sighting_id', sightingId)
        .order('created_at', { ascending: false }),
    );
  }

  async listOpenForExpert(token: string, userId: string) {
    const client = this.supabase.createClient(token);
    const profile = assertNoError(
      await client.from('users').select('taxonomy_expert').eq('id', userId).single(),
    );
    if (!profile?.taxonomy_expert) {
      throw new ForbiddenException('Taxonomy expert role required');
    }

    return assertNoError(
      await client
        .from('sighting_corrections')
        .select(
          '*, reporter:users!sighting_corrections_reporter_id_fkey(username, full_name), sighting:sightings(id, species_id, user_id), proposed:species!sighting_corrections_proposed_species_id_fkey(scientific_name, common_name)',
        )
        .eq('status', 'open')
        .order('created_at', { ascending: true })
        .limit(50),
    );
  }

  async expertResolve(
    token: string,
    userId: string,
    correctionId: string,
    action: 'accept' | 'reject',
  ) {
    const client = this.supabase.createClient(token);
    const profile = assertNoError(
      await client.from('users').select('taxonomy_expert').eq('id', userId).single(),
    );
    if (!profile?.taxonomy_expert) {
      throw new ForbiddenException('Taxonomy expert role required');
    }

    const correction = assertNoError(
      await client
        .from('sighting_corrections')
        .select('*, sighting:sightings(id, user_id, species_id, correction_log)')
        .eq('id', correctionId)
        .maybeSingle(),
    );
    if (!correction || correction.status !== 'open') {
      throw new NotFoundException('Open correction not found');
    }

    if (action === 'reject') {
      return assertNoError(
        await client
          .from('sighting_corrections')
          .update({
            status: 'rejected',
            resolver_id: userId,
            resolved_at: new Date().toISOString(),
          })
          .eq('id', correctionId)
          .select('*')
          .single(),
      );
    }

    const sighting = correction.sighting as {
      id: string;
      user_id: string;
      species_id: string;
      correction_log: unknown[];
    };

    const logEntry = {
      from_species_id: sighting.species_id,
      to_species_id: correction.proposed_species_id,
      by: userId,
      at: new Date().toISOString(),
      reason: correction.reason,
      expert: true,
    };

    await client
      .from('sightings')
      .update({
        species_id: correction.proposed_species_id,
        correction_log: [...(sighting.correction_log ?? []), logEntry],
        updated_at: new Date().toISOString(),
      })
      .eq('id', sighting.id);

    return assertNoError(
      await client
        .from('sighting_corrections')
        .update({
          status: 'accepted',
          resolver_id: userId,
          resolved_at: new Date().toISOString(),
        })
        .eq('id', correctionId)
        .select('*')
        .single(),
    );
  }
}
