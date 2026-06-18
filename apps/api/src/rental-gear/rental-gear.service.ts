import { randomBytes } from 'crypto';
import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';

@Injectable()
export class RentalGearService {
  constructor(private readonly supabase: SupabaseService) {}

  async list(token: string, operatorId: string) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('operator_rental_gear')
        .select('*')
        .eq('operator_id', operatorId)
        .eq('is_active', true)
        .order('label'),
    );
  }

  async create(
    token: string,
    operatorId: string,
    dto: { gear_type: string; label: string; serial_number?: string },
  ) {
    const client = this.supabase.createClient(token);
    const qr = `ogr_${randomBytes(8).toString('hex')}`;
    return assertNoError(
      await client
        .from('operator_rental_gear')
        .insert({
          operator_id: operatorId,
          gear_type: dto.gear_type,
          label: dto.label,
          serial_number: dto.serial_number ?? null,
          qr_code: qr,
        })
        .select('*')
        .single(),
    );
  }

  async checkout(token: string, operatorId: string, qrCode: string, userId: string) {
    const client = this.supabase.createClient(token);
    const row = assertNoError(
      await client
        .from('operator_rental_gear')
        .update({
          checked_out_to: userId,
          checked_out_at: new Date().toISOString(),
        })
        .eq('operator_id', operatorId)
        .eq('qr_code', qrCode)
        .select('*')
        .maybeSingle(),
    );
    if (!row) throw new NotFoundException('Gear not found');
    return row;
  }

  async checkin(token: string, operatorId: string, qrCode: string) {
    const client = this.supabase.createClient(token);
    const existing = assertNoError(
      await client
        .from('operator_rental_gear')
        .select('dives_since_service')
        .eq('operator_id', operatorId)
        .eq('qr_code', qrCode)
        .maybeSingle(),
    );
    if (!existing) throw new NotFoundException('Gear not found');

    const row = assertNoError(
      await client
        .from('operator_rental_gear')
        .update({
          checked_out_to: null,
          checked_out_at: null,
          dives_since_service: (existing.dives_since_service as number) + 1,
        })
        .eq('operator_id', operatorId)
        .eq('qr_code', qrCode)
        .select('*')
        .single(),
    );
    return row;
  }
}
