import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';
import { CreateTripDto } from '../gear/dto/gear.dto';

@Injectable()
export class TripsService {
  constructor(private readonly supabase: SupabaseService) {}

  async list(token: string, userId: string) {
    const client = this.supabase.createClient(token);
    const asLeader = assertNoError(
      await client.from('trips').select('*').eq('leader_id', userId),
    );
    const memberRows = assertNoError(
      await client
        .from('trip_members')
        .select('trip:trips(*)')
        .eq('user_id', userId),
    );
    const memberTrips = (memberRows ?? [])
      .map((r) => r.trip)
      .filter(Boolean);
    const merged = [...(asLeader ?? []), ...memberTrips];
    const seen = new Set<string>();
    return merged.filter((t) => {
      const trip = t as { id: string };
      if (seen.has(trip.id)) return false;
      seen.add(trip.id);
      return true;
    });
  }

  async create(token: string, userId: string, dto: CreateTripDto) {
    const client = this.supabase.createClient(token);
    const trip = assertNoError(
      await client
        .from('trips')
        .insert({
          leader_id: userId,
          name: dto.name,
          start_date: dto.start_date,
          end_date: dto.end_date,
          region: dto.region ?? null,
          operator_id: dto.operator_id ?? null,
          notes: dto.notes ?? null,
        })
        .select('*')
        .single(),
    );

    await client.from('trip_members').insert({
      trip_id: trip.id,
      user_id: userId,
      role: 'leader',
    });

    if (dto.site_ids?.length) {
      await client.from('trip_sites').insert(
        dto.site_ids.map((siteId, i) => ({
          trip_id: trip.id,
          dive_site_id: siteId,
          sort_order: i,
        })),
      );
    }

    return trip;
  }

  async getById(token: string, userId: string, tripId: string) {
    const client = this.supabase.createClient(token);
    const trip = assertNoError(
      await client.from('trips').select('*').eq('id', tripId).maybeSingle(),
    );
    if (!trip) throw new NotFoundException('Trip not found');

    const isMember = assertNoError(
      await client
        .from('trip_members')
        .select('id')
        .eq('trip_id', tripId)
        .eq('user_id', userId)
        .maybeSingle(),
    );
    if (trip.leader_id !== userId && !isMember) {
      throw new NotFoundException('Trip not found');
    }

    const members = assertNoError(
      await client
        .from('trip_members')
        .select('*, user:users(id, username, full_name, avatar_url)')
        .eq('trip_id', tripId),
    );
    const sites = assertNoError(
      await client
        .from('trip_sites')
        .select('*, site:dive_sites(id, name, slug)')
        .eq('trip_id', tripId)
        .order('sort_order'),
    );

    return { ...trip, members, sites };
  }

  async getRecap(token: string, userId: string, tripId: string) {
    await this.getById(token, userId, tripId);
    const client = this.supabase.createClient(token);
    return assertNoError(await client.rpc('trip_recap', { p_trip_id: tripId }));
  }

  async inviteMember(
    token: string,
    userId: string,
    tripId: string,
    username: string,
  ) {
    const trip = await this.getById(token, userId, tripId);
    if (trip.leader_id !== userId) {
      throw new NotFoundException('Only trip leader can invite members');
    }

    const client = this.supabase.createClient(token);
    const invitee = assertNoError(
      await client.from('users').select('id').eq('username', username).maybeSingle(),
    );
    if (!invitee) throw new NotFoundException(`User "${username}" not found`);

    return assertNoError(
      await client
        .from('trip_members')
        .upsert(
          { trip_id: tripId, user_id: invitee.id, role: 'member' },
          { onConflict: 'trip_id,user_id' },
        )
        .select('*, user:users(id, username, full_name)')
        .single(),
    );
  }

  async getCalendarIcs(token: string, userId: string, tripId: string): Promise<string> {
    const detail = await this.getById(token, userId, tripId);
    const trip = detail as {
      name: string;
      start_date: string;
      end_date: string;
      region: string | null;
      sites: Array<{ site: { name: string; slug: string } | null }>;
    };

    const uid = `trip-${tripId}@benthyo.com`;
    const dtStart = trip.start_date.replace(/-/g, '');
    const dtEnd = trip.end_date.replace(/-/g, '');
    const siteNames = (trip.sites ?? [])
      .map((s) => s.site?.name)
      .filter(Boolean)
      .join(', ');

    const lines = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Benthyo//Trip Calendar//EN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'BEGIN:VEVENT',
      `UID:${uid}`,
      `DTSTAMP:${new Date().toISOString().replace(/[-:]/g, '').split('.')[0]}Z`,
      `DTSTART;VALUE=DATE:${dtStart}`,
      `DTEND;VALUE=DATE:${dtEnd}`,
      `SUMMARY:${this.icsEscape(trip.name)}`,
      `DESCRIPTION:${this.icsEscape(siteNames || trip.region || 'Dive trip')}`,
      'END:VEVENT',
      'END:VCALENDAR',
    ];
    return lines.join('\r\n');
  }

  private icsEscape(value: string): string {
    return value.replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\n/g, '\\n');
  }
}
