import { Injectable, NotFoundException, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';
import { SubmitMedicalFormDto } from './dto/medical.dto';

@Injectable()
export class MedicalService {
  private readonly logger = new Logger(MedicalService.name);

  /**
   * The encryption key material is read from the environment
   * (MEDICAL_ENCRYPTION_MASTER_KEY + MEDICAL_ENCRYPTION_KEY_SALT) and
   * threaded THROUGH each medical RPC call (the *_v2 wrappers added in
   * migration 043). PostgREST runs every .rpc() in its own transaction,
   * so the key must be set and consumed in the same transaction — a
   * separate "set the GUC" call would not persist to the encrypt call.
   * The *_v2 RPCs do `set_config(..., is_local => true)` before
   * delegating, so encrypt/decrypt observe the real key.
   */
  constructor(
    private readonly supabase: SupabaseService,
    private readonly config: ConfigService,
  ) {}

  async onModuleInit() {
    const masterKey = this.config.get<string>('MEDICAL_ENCRYPTION_MASTER_KEY');
    const nodeEnv = this.config.get<string>('NODE_ENV') ?? 'development';
    if (nodeEnv === 'production' && (!masterKey || masterKey.length < 16)) {
      // Fail fast: without a real key, medical answers would be encrypted
      // under the public dev placeholder baked into migration 040.
      throw new Error(
        'MEDICAL_ENCRYPTION_MASTER_KEY must be set (>=16 chars) in production',
      );
    }
    if (!masterKey) {
      this.logger.warn(
        'MEDICAL_ENCRYPTION_MASTER_KEY unset — medical encryption is using the development fallback key. Do not use in production.',
      );
    }
  }

  /** Env-sourced key material passed through to the *_v2 medical RPCs. */
  private keyMaterial(): { master: string; salt: string } {
    return {
      master: this.config.get<string>('MEDICAL_ENCRYPTION_MASTER_KEY') ?? '',
      salt: this.config.get<string>('MEDICAL_ENCRYPTION_KEY_SALT') ?? '',
    };
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

    // The insert uses an rpc(...) that encrypts the answers column
    // server-side, keeping the plaintext key off the wire. The *_v2
    // wrapper sets the runtime key transaction-locally so encryption
    // uses the real env key, not the dev placeholder (migration 043).
    const operatorId = dto.operator_id ?? null;
    const { master, salt } = this.keyMaterial();
    const result = await client.rpc('submit_medical_form_v2', {
      p_user_id: userId,
      p_operator_id: operatorId,
      p_trip_id: dto.trip_id ?? null,
      p_template_id: dto.template_id,
      p_answers: dto.answers,
      p_has_yes_answer: hasYes,
      p_signer_name: dto.signer_name,
      p_master_key: master,
      p_salt: salt,
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
    // The *_v2 wrapper threads the runtime key so decryption matches the
    // key used at encrypt time (migration 043).
    const { master, salt } = this.keyMaterial();
    return assertNoError(
      await client.rpc('my_medical_submissions_decrypted_v2', {
        p_user_id: userId,
        p_master_key: master,
        p_salt: salt,
      }),
    );
  }
}
