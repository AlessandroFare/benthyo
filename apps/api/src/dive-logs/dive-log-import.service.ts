import { BadRequestException, Injectable } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { CreateDiveLogDto } from './dto/dive-log.dto';
import { DiveLogsService } from './dive-logs.service';
import { parseUddfXml } from './uddf.parser';

@Injectable()
export class DiveLogImportService {
  constructor(
    private readonly diveLogs: DiveLogsService,
    private readonly supabase: SupabaseService,
  ) {}

  async importUddf(
    token: string,
    userId: string,
    xml: string,
  ): Promise<{ imported: number; skipped: number; logs: unknown[] }> {
    const parsed = parseUddfXml(xml);
    if (parsed.dives.length === 0) {
      throw new BadRequestException(
        'No dives found in file. Export UDDF/UDCF from your dive computer app.',
      );
    }

    const client = this.supabase.createClient(token);
    const created: unknown[] = [];
    let skipped = 0;

    for (const dive of parsed.dives) {
      let diveSiteId: string | undefined;
      if (dive.siteName) {
        const siteResult = await client
          .from('dive_sites')
          .select('id')
          .ilike('name', dive.siteName)
          .limit(1)
          .maybeSingle();
        if (!siteResult.error && siteResult.data) {
          diveSiteId = siteResult.data.id as string;
        }
      }

      const notesParts = [
        'Imported from dive computer (UDDF)',
        dive.siteName ? `Site: ${dive.siteName}` : null,
        parsed.generator ? `Device: ${parsed.generator}` : null,
        dive.profileSamples.length > 0
          ? `Profile samples: ${dive.profileSamples.length}`
          : null,
      ].filter(Boolean);

      const dto: CreateDiveLogDto = {
        dive_date: dive.diveDate,
        dive_site_id: diveSiteId,
        max_depth_m: dive.maxDepthM,
        avg_depth_m: dive.avgDepthM,
        duration_min: dive.durationMin,
        water_temp_bottom_c: dive.waterTempC,
        notes: notesParts.join(' · '),
        profile_samples:
          dive.profileSamples.length > 0
            ? dive.profileSamples.map((s) => ({
                t_sec: s.timeSec,
                depth_m: s.depthM,
              }))
            : undefined,
      };

      try {
        const log = await this.diveLogs.create(token, userId, dto);
        created.push(log);
      } catch {
        skipped += 1;
      }
    }

    return { imported: created.length, skipped, logs: created };
  }
}
