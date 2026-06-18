import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { DiveLog } from '../database/database.types';
import { assertNoError } from '../common/utils/supabase-error.util';
import { paginated, PaginatedResult } from '../common/dto/pagination.dto';
import {
  CreateDiveLogDto,
  ListDiveLogsDto,
  SyncDiveLogsDto,
  UpdateDiveLogDto,
} from './dto/dive-log.dto';

@Injectable()
export class DiveLogsService {
  constructor(private readonly supabase: SupabaseService) {}

  async list(token: string, userId: string, query: ListDiveLogsDto): Promise<PaginatedResult<DiveLog>> {
    const client = this.supabase.createClient(token);

    const result = await client
      .from('dive_logs')
      .select('*', { count: 'exact' })
      .eq('user_id', userId)
      .order('dive_date', { ascending: false })
      .range(query.offset, query.offset + query.limit - 1);

    if (result.error) assertNoError(result);

    return paginated(
      (result.data ?? []) as DiveLog[],
      result.count ?? 0,
      query.page,
      query.limit,
    );
  }

  async getById(token: string, userId: string, id: string): Promise<DiveLog> {
    const client = this.supabase.createClient(token);

    const log = assertNoError(
      await client
        .from('dive_logs')
        .select('*')
        .eq('id', id)
        .eq('user_id', userId)
        .maybeSingle(),
    );

    if (!log) throw new NotFoundException('Dive log not found');
    return log as DiveLog;
  }

  async create(token: string, userId: string, dto: CreateDiveLogDto): Promise<DiveLog> {
    const client = this.supabase.createClient(token);

    const log = assertNoError(
      await client
        .from('dive_logs')
        .insert({
          ...dto,
          profile_samples: dto.profile_samples ?? null,
          user_id: userId,
          synced_at: new Date().toISOString(),
        })
        .select('*')
        .single(),
    ) as DiveLog;

    return log;
  }

  async update(token: string, userId: string, id: string, dto: UpdateDiveLogDto): Promise<DiveLog> {
    const client = this.supabase.createClient(token);

    const log = assertNoError(
      await client
        .from('dive_logs')
        .update({ ...dto, synced_at: new Date().toISOString() })
        .eq('id', id)
        .eq('user_id', userId)
        .select('*')
        .single(),
    ) as DiveLog;

    return log;
  }

  async remove(token: string, userId: string, id: string): Promise<{ deleted: true }> {
    const client = this.supabase.createClient(token);
    assertNoError(
      await client.from('dive_logs').delete().eq('id', id).eq('user_id', userId),
    );
    return { deleted: true };
  }

  async getStats(token: string, userId: string): Promise<Record<string, unknown>> {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client.rpc('user_dive_stats', { p_user_id: userId }),
    ) as Record<string, unknown>;
  }

  async sync(token: string, userId: string, dto: SyncDiveLogsDto): Promise<DiveLog[]> {
    const client = this.supabase.createClient(token);
    const synced: DiveLog[] = [];

    for (const logDto of dto.logs) {
      const log = assertNoError(
        await client
          .from('dive_logs')
          .insert({ ...logDto, user_id: userId, synced_at: new Date().toISOString() })
          .select('*')
          .single(),
      ) as DiveLog;
      synced.push(log);
    }

    return synced;
  }
}
