import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';
import { CreateGearItemDto, UpdateGearItemDto } from './dto/gear.dto';

@Injectable()
export class GearService {
  constructor(private readonly supabase: SupabaseService) {}

  async list(token: string, userId: string) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('gear_items')
        .select('*')
        .eq('user_id', userId)
        .order('name'),
    );
  }

  async create(token: string, userId: string, dto: CreateGearItemDto) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('gear_items')
        .insert({ ...dto, user_id: userId })
        .select('*')
        .single(),
    );
  }

  async update(
    token: string,
    userId: string,
    id: string,
    dto: UpdateGearItemDto,
  ) {
    const client = this.supabase.createClient(token);
    const row = assertNoError(
      await client
        .from('gear_items')
        .update({ ...dto, updated_at: new Date().toISOString() })
        .eq('id', id)
        .eq('user_id', userId)
        .select('*')
        .maybeSingle(),
    );
    if (!row) throw new NotFoundException('Gear item not found');
    return row;
  }

  async delete(token: string, userId: string, id: string) {
    const client = this.supabase.createClient(token);
    const { error } = await client
      .from('gear_items')
      .delete()
      .eq('id', id)
      .eq('user_id', userId);
    if (error) throw error;
  }

  async listServiceDue(token: string, userId: string) {
    const client = this.supabase.createClient(token);
    const items = assertNoError(
      await client.from('gear_items').select('*').eq('user_id', userId),
    );

    const now = new Date();
    return (items ?? []).filter((item) => {
      const row = item as {
        last_service_date: string | null;
        service_interval_months: number | null;
        dives_since_service: number;
      };
      if (row.service_interval_months && row.last_service_date) {
        const due = new Date(row.last_service_date);
        due.setMonth(due.getMonth() + row.service_interval_months);
        if (due <= now) return true;
      }
      return row.dives_since_service >= 50;
    });
  }
}
