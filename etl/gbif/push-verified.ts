import 'dotenv/config';
import { createHash } from 'crypto';
import { logger, logJobSummary } from '../shared/logger';
import { getSupabase } from '../shared/supabase';

/**
 * Push user-opted verified sightings to GBIF export batch log.
 * Run via cron: pnpm --filter @oceanlog/etl gbif:push
 */
async function main(): Promise<void> {
  const supabase = getSupabase();
  const started = Date.now();

  const { data: users, error: usersError } = await supabase
    .from('users')
    .select('id, username')
    .eq('gbif_export_opt_in', true);

  if (usersError) throw usersError;

  let totalSightings = 0;
  let batches = 0;

  for (const user of users ?? []) {
    const { data: sightings, error } = await supabase
      .from('sightings')
      .select('id, species_id, dive_site_id, observed_at, depth_m, photo_urls')
      .eq('user_id', user.id)
      .not('verified_by', 'is', null)
      .is('gbif_exported_at', null);

    if (error) {
      logger.warn(`Skip user ${user.id}: ${error.message}`);
      continue;
    }

    const ids = (sightings ?? []).map((s) => s.id as string);
    if (ids.length === 0) continue;

    const now = new Date().toISOString();
    await supabase.from('sightings').update({ gbif_exported_at: now }).in('id', ids);

    await supabase.from('gbif_export_batches').insert({
      user_id: user.id,
      sighting_count: ids.length,
      status: 'completed',
    });

    totalSightings += ids.length;
    batches += 1;
    logger.info(`GBIF batch for ${user.username}: ${ids.length} sightings`);
  }

  logger.info('gbif-push-verified ETL complete', {
    durationMs: Date.now() - started,
    users: users?.length ?? 0,
    batches,
    sightings: totalSightings,
  });
}

main().catch((err) => {
  logger.error(String(err));
  process.exit(1);
});

export function fingerprintRecord(id: string, observedAt: string): string {
  return createHash('sha256').update(`${id}:${observedAt}`).digest('hex');
}
