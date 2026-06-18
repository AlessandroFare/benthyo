import { Injectable } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';
import { CreateSiteReviewDto } from './dto/review.dto';

@Injectable()
export class ReviewsService {
  constructor(private readonly supabase: SupabaseService) {}

  async create(token: string, userId: string, dto: CreateSiteReviewDto) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('site_reviews')
        .insert({
          user_id: userId,
          dive_site_id: dto.dive_site_id,
          dive_log_id: dto.dive_log_id ?? null,
          rating: dto.rating,
          body: dto.body ?? null,
          visibility_m: dto.visibility_m ?? null,
          current_note: dto.current_note ?? null,
        })
        .select('*')
        .single(),
    );
  }

  async listForSite(token: string | undefined, siteId: string) {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();
    return assertNoError(
      await client
        .from('site_reviews')
        .select('*, user:users(username, full_name)')
        .eq('dive_site_id', siteId)
        .order('created_at', { ascending: false })
        .limit(20),
    );
  }
}
