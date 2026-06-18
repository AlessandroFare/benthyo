import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';
import {
  CreateMarketplaceListingDto,
  UpdateMarketplaceListingDto,
} from './dto/marketplace.dto';

@Injectable()
export class MarketplaceService {
  constructor(private readonly supabase: SupabaseService) {}

  async listPublic(region?: string, listingType?: string) {
    const client = this.supabase.anonClient();
    let query = client
      .from('operator_marketplace_listings')
      .select('*, operator:operators(id, name, slug, country_code)')
      .eq('is_active', true)
      .order('created_at', { ascending: false })
      .limit(50);

    if (region) query = query.ilike('region', `%${region}%`);
    if (listingType) query = query.eq('listing_type', listingType);

    return assertNoError(await query);
  }

  async listForOperator(token: string, operatorId: string) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('operator_marketplace_listings')
        .select('*')
        .eq('operator_id', operatorId)
        .order('created_at', { ascending: false }),
    );
  }

  async create(token: string, operatorId: string, dto: CreateMarketplaceListingDto) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('operator_marketplace_listings')
        .insert({
          operator_id: operatorId,
          listing_type: dto.listing_type,
          title: dto.title,
          description: dto.description,
          price_cents: dto.price_cents,
          currency: dto.currency ?? 'EUR',
          region: dto.region ?? null,
        })
        .select('*')
        .single(),
    );
  }

  async update(
    token: string,
    operatorId: string,
    id: string,
    dto: UpdateMarketplaceListingDto,
  ) {
    const client = this.supabase.createClient(token);
    const row = assertNoError(
      await client
        .from('operator_marketplace_listings')
        .update({ ...dto, updated_at: new Date().toISOString() })
        .eq('id', id)
        .eq('operator_id', operatorId)
        .select('*')
        .maybeSingle(),
    );
    if (!row) throw new NotFoundException('Listing not found');
    return row;
  }
}
