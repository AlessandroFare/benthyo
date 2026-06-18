import { Injectable, NotFoundException } from '@nestjs/common';
import { createHash } from 'crypto';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';
import { SignWaiverDto, UpsertOperatorWaiverDto } from './dto/waiver.dto';

interface SignatureContext {
  ip: string;
  userAgent: string;
}

@Injectable()
export class WaiversService {
  constructor(private readonly supabase: SupabaseService) {}

  async getActiveByOperatorSlug(slug: string) {
    const client = this.supabase.anonClient();
    const operator = assertNoError(
      await client
        .from('operators')
        .select('id, name, slug')
        .eq('slug', slug)
        .maybeSingle(),
    );
    if (!operator) throw new NotFoundException('Operator not found');

    const waiver = assertNoError(
      await client
        .from('operator_waivers')
        .select('*')
        .eq('operator_id', operator.id)
        .eq('is_active', true)
        .order('version', { ascending: false })
        .limit(1)
        .maybeSingle(),
    );

    return { operator, waiver };
  }

  /**
   * Sign a waiver. Captures IP, User-Agent, signer email, and a SHA256
   * of the waiver body (DD-5.7 — eIDAS SES compliance).
   */
  async sign(
    token: string,
    userId: string,
    dto: SignWaiverDto,
    ctx: SignatureContext,
  ) {
    const client = this.supabase.createClient(token);

    // Load the waiver (must be active) and compute its body hash.
    const waiver = assertNoError(
      await client
        .from('operator_waivers')
        .select('id, operator_id, is_active, body, version')
        .eq('id', dto.waiver_id)
        .maybeSingle(),
    );
    if (!waiver?.is_active) {
      throw new NotFoundException('Waiver not found or no longer active');
    }

    const waiverBodyHash = createHash('sha256')
      .update(String(waiver.body ?? ''))
      .digest('hex');

    // Resolve the signer's email from the Supabase auth admin endpoint
    // (service-role-scoped read on auth.users; the caller cannot do this
    // from a regular RLS-aware client).
    const admin = this.supabase.serviceRole();
    const { data: authUser } = await admin.auth.admin.getUserById(userId);
    const signerEmail = authUser?.user?.email ?? null;

    return assertNoError(
      await client
        .from('waiver_signatures')
        .upsert(
          {
            waiver_id: dto.waiver_id,
            operator_id: waiver.operator_id,
            user_id: userId,
            signer_name: dto.signer_name,
            signer_email: signerEmail,
            ip_address: ctx.ip,
            user_agent: ctx.userAgent,
            signed_waiver_text_hash: waiverBodyHash,
            signed_waiver_version: waiver.version,
            signed_at: new Date().toISOString(),
          },
          { onConflict: 'waiver_id,user_id' },
        )
        .select('*')
        .single(),
    );
  }

  /**
   * Publish a new waiver version. Deactivates prior active waivers
   * for the same operator and inserts a new row.
   */
  async upsertForOperator(
    token: string,
    operatorId: string,
    dto: UpsertOperatorWaiverDto,
  ) {
    const client = this.supabase.createClient(token);

    await client
      .from('operator_waivers')
      .update({ is_active: false })
      .eq('operator_id', operatorId)
      .eq('is_active', true);

    return assertNoError(
      await client
        .from('operator_waivers')
        .insert({
          operator_id: operatorId,
          title: dto.title,
          body: dto.body,
          version: 1,
          is_active: true,
        })
        .select('*')
        .single(),
    );
  }
}
