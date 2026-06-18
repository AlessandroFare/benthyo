import { Injectable } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';
import { CreateDiveLogDto } from '../dive-logs/dto/dive-log.dto';
import { DiveLogsService } from '../dive-logs/dive-logs.service';
import { BleImportDto, RegisterBleDeviceDto } from './dto/ble-sync.dto';

@Injectable()
export class BleSyncService {
  constructor(
    private readonly supabase: SupabaseService,
    private readonly diveLogs: DiveLogsService,
  ) {}

  async listDevices(token: string, userId: string) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('dive_computer_devices')
        .select('*')
        .eq('user_id', userId)
        .order('last_sync_at', { ascending: false, nullsFirst: false }),
    );
  }

  async registerDevice(token: string, userId: string, dto: RegisterBleDeviceDto) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('dive_computer_devices')
        .upsert(
          {
            user_id: userId,
            device_name: dto.device_name,
            device_uuid: dto.device_uuid,
            manufacturer: dto.manufacturer ?? null,
            model: dto.model ?? null,
          },
          { onConflict: 'user_id,device_uuid' },
        )
        .select('*')
        .single(),
    );
  }

  async importDives(token: string, userId: string, dto: BleImportDto) {
    const client = this.supabase.createClient(token);
    const device = assertNoError(
      await client
        .from('dive_computer_devices')
        .select('id, device_name')
        .eq('user_id', userId)
        .eq('device_uuid', dto.device_uuid)
        .maybeSingle(),
    );

    const deviceLabel = device?.device_name ?? dto.device_uuid;
    const created: unknown[] = [];
    let skipped = 0;

    for (const dive of dto.dives) {
      const logDto: CreateDiveLogDto = {
        dive_date: dive.dive_date,
        max_depth_m: dive.max_depth_m,
        avg_depth_m: Math.round(dive.max_depth_m * 0.65 * 10) / 10,
        duration_min: dive.duration_min,
        notes: `Imported via BLE from ${deviceLabel}`,
        profile_samples: dive.profile_samples,
      };

      try {
        const log = await this.diveLogs.create(token, userId, logDto);
        created.push(log);
      } catch {
        skipped += 1;
      }
    }

    if (device) {
      await client
        .from('dive_computer_devices')
        .update({ last_sync_at: new Date().toISOString() })
        .eq('id', device.id);
    }

    return { imported: created.length, skipped, logs: created };
  }
}
