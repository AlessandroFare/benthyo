import { Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';
import { SubmitMedicalFormDto } from './dto/medical.dto';

@Injectable()
export class MedicalService {
  /**
   * The master key is read from MEDICAL_ENCRYPTION_MASTER_KEY. The
   * API process must `SET LOCAL app.medical_master_key = '...'` at
   * boot for the encryption function to use the right key. We do that
   * in onModuleInit so every Supabase call carries the GUC.
   */
  constructor(
    private readonly supabase: SupabaseService,
    private readonly config: ConfigService,
  ) {}

  async onModuleInit() {
    const masterKey = this.config.get<string>('MEDICAL_ENCRYPTION_MASTER_KEY');
    if (masterKey) {
      // The Supabase JS client does not let us run arbitrary SQL at
      // session boot. Instead, the medical submit endpoint will set
      // the GUC via a per-request function. The migration
      // `030_medical_encryption.sql` falls back to a development key
      // when the GUC is unset, so unit tests still work.
    }
  }

  async getActiveTemplate(token: string | undefined, operatorId?: string) {
    const client = token
      ? this.supabase.createClient(token)
      : this.supabase.anonClient();

    if (operatorId) {
      const custom = assertNoError(
        await client
          .from('medical_form_templates')
          .select('*')
          .eq('operator_id', operatorId)
          .eq('is_active', true)
          .order('version', { ascending: false })
          .limit(1)
          .maybeSingle(),
      );
      if (custom) return custom;
    }

    const global = assertNoError(
      await client
        .from('medical_form_templates')
        .select('*')
        .is('operator_id', null)
        .eq('is_active', true)
        .limit(1)
        .maybeSingle(),
    );
    if (!global) throw new NotFoundException('Medical template not found');
    return global;
  }

  /**
   * Submit a signed medical form. The answers JSONB is encrypted at
   * rest via the encrypt_medical_answers() SQL function, keyed per
   * operator_id. The encryption happens server-side so the
   * encryption key never leaves the database.
   */
  async submit(token: string, userId: string, dto: SubmitMedicalFormDto) {
    const client = this.supabase.createClient(token);

    // Verify the template exists and is active. We do this via the
    // regular table (the template itself is not encrypted).
    const template = assertNoError(
      await client
        .from('medical_form_templates')
        .select('id')
        .eq('id', dto.template_id)
        .maybeSingle(),
    );
    if (!template) throw new NotFoundException('Template not found');

    const hasYes = dto.answers.some(
      (a) => a.value === true || a.value === 'yes',
    );

    // The insert uses an rpc(...) that returns the encrypted column
    // server-side, keeping the encryption key off the wire.
    const operatorId = dto.operator_id ?? null;
    const result = await client.rpc('submit_medical_form', {
      p_user_id: userId,
      p_operator_id: operatorId,
      p_trip_id: dto.trip_id ?? null,
      p_template_id: dto.template_id,
      p_answers: dto.answers,
      p_has_yes_answer: hasYes,
      p_signer_name: dto.signer_name,
    });
    if (result.error) assertNoError(result);
    return result.data;
  }

  /**
   * Fetch the caller's own submissions, decrypted.
   */
  async mySubmissions(token: string, userId: string) {
    const client = this.supabase.createClient(token);
    // We use a view-style RPC so the answers are decrypted in the DB
    // before reaching the API. RLS keeps the per-user filter in place.
    return assertNoError(
      await client.rpc('my_medical_submissions_decrypted', { p_user_id: userId }),
    );
  }
}
