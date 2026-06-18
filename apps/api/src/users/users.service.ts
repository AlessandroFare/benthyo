import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { UserProfile, UserBadge, UserLifeList } from '../database/database.types';
import { assertNoError } from '../common/utils/supabase-error.util';
import { UpdateUserDto } from './dto/update-user.dto';

@Injectable()
export class UsersService {
  constructor(private readonly supabase: SupabaseService) {}

  async getMe(token: string): Promise<UserProfile> {
    const client = this.supabase.createClient(token);
    const { data: { user } } = await client.auth.getUser(token);
    if (!user) {
      throw new NotFoundException('User not found');
    }

    return assertNoError(
      await client.from('users').select('*').eq('id', user.id).single(),
    ) as UserProfile;
  }

  async updateMe(token: string, userId: string, dto: UpdateUserDto): Promise<UserProfile> {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('users')
        .update({ ...dto, updated_at: new Date().toISOString() })
        .eq('id', userId)
        .select('*')
        .single(),
    ) as UserProfile;
  }

  async getByUsername(token: string | undefined, username: string): Promise<UserProfile> {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    const profile = assertNoError(
      await client
        .from('users')
        .select('*')
        .eq('username', username)
        .maybeSingle(),
    );

    if (!profile) {
      throw new NotFoundException(`User "${username}" not found`);
    }

    return profile as UserProfile;
  }

  async getLifeList(token: string, userId: string): Promise<UserLifeList[]> {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('user_life_list')
        .select('*')
        .eq('user_id', userId)
        .order('first_seen_at', { ascending: false }),
    ) as UserLifeList[];
  }

  async getBadges(token: string, userId: string): Promise<(UserBadge & { badge: unknown })[]> {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('user_badges')
        .select('*, badge:badges(*)')
        .eq('user_id', userId)
        .order('earned_at', { ascending: false }),
    ) as (UserBadge & { badge: unknown })[];
  }

  async getConservationAlerts(token: string, userId: string) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client.rpc('conservation_alerts_for_user', { p_user_id: userId }),
    );
  }

  async getPublicLogbook(token: string | undefined, username: string) {
    const profile = await this.getByUsername(token, username);
    const client = this.supabase.anonClient();

    if (!(profile as { public_logbook?: boolean }).public_logbook) {
      return {
        profile: {
          username: profile.username,
          full_name: profile.full_name,
          total_dives: profile.total_dives,
        },
        public: false,
        dives: [],
      };
    }

    const dives = assertNoError(
      await client
        .from('dive_logs')
        .select('id, dive_date, max_depth_m, duration_min, dive_site_id')
        .eq('user_id', profile.id)
        .order('dive_date', { ascending: false })
        .limit(20),
    );

    const verification = assertNoError(
      await client.rpc('diver_verification_level', { p_user_id: profile.id }),
    );

    const lifeList = assertNoError(
      await client
        .from('user_life_list')
        .select('*, species:species(id, scientific_name, common_name)')
        .eq('user_id', profile.id)
        .order('first_seen_at', { ascending: false })
        .limit(50),
    );

    return {
      profile,
      public: true,
      verification,
      dives,
      life_list: lifeList,
    };
  }
}
