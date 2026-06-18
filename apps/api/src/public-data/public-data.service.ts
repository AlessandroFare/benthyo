import { Injectable, NotFoundException } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';
import { DiveSitesService } from '../dive-sites/dive-sites.service';

@Injectable()
export class PublicDataService {
  constructor(
    private readonly supabase: SupabaseService,
    private readonly diveSites: DiveSitesService,
  ) {}

  private async resolveSiteId(slugOrId: string): Promise<string> {
    try {
      const site = await this.diveSites.getById(undefined, slugOrId);
      return site.id;
    } catch {
      const site = await this.diveSites.getBySlug(undefined, slugOrId);
      return site.id;
    }
  }

  async getSiteCard(slugOrId: string): Promise<unknown> {
    const siteId = await this.resolveSiteId(slugOrId);
    const client = this.supabase.anonClient();
    const data = assertNoError(
      await client.rpc('site_public_card', { p_site_id: siteId }),
    );
    if (!data) throw new NotFoundException('Site not found');
    return data;
  }

  async getPrepCard(slugOrId: string): Promise<unknown> {
    const siteId = await this.resolveSiteId(slugOrId);
    const client = this.supabase.anonClient();
    const data = assertNoError(
      await client.rpc('site_prep_card', { p_site_id: siteId }),
    );
    if (!data) throw new NotFoundException('Site not found');
    return data;
  }

  async getDiverVerification(userId: string): Promise<unknown> {
    const client = this.supabase.anonClient();
    return assertNoError(
      await client.rpc('diver_verification_level', { p_user_id: userId }),
    );
  }

  async getGuestBriefing(slug: string) {
    const client = this.supabase.anonClient();
    const operator = assertNoError(
      await client
        .from('operators')
        .select('id, name, slug, email, website')
        .eq('slug', slug)
        .maybeSingle(),
    );
    if (!operator) throw new NotFoundException('Operator not found');

    const waiver = assertNoError(
      await client
        .from('operator_waivers')
        .select('title, body, version, created_at')
        .eq('operator_id', operator.id)
        .eq('is_active', true)
        .maybeSingle(),
    );

    return {
      operator: {
        name: operator.name,
        slug: operator.slug,
        email: operator.email,
        website: operator.website,
      },
      waiver: waiver
        ? { title: waiver.title, excerpt: (waiver.body as string).slice(0, 280) }
        : null,
      links: {
        sign_waiver: `/waiver/${slug}`,
        medical_form: `/medical?operatorId=${operator.id}`,
      },
    };
  }
}
