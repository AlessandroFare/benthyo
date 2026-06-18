import { Injectable } from '@nestjs/common';
import { createHash, randomBytes } from 'crypto';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';
import { CreateApiKeyDto } from '../medical/dto/medical.dto';

@Injectable()
export class ApiKeysService {
  constructor(private readonly supabase: SupabaseService) {}

  async list(token: string, userId: string) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('api_keys')
        .select('id, name, key_prefix, created_at, last_used_at, revoked_at')
        .eq('user_id', userId)
        .is('revoked_at', null)
        .order('created_at', { ascending: false }),
    );
  }

  async create(token: string, userId: string, dto: CreateApiKeyDto) {
    const client = this.supabase.createClient(token);
    const raw = `ol_${randomBytes(24).toString('hex')}`;
    const keyHash = createHash('sha256').update(raw).digest('hex');
    const prefix = raw.slice(0, 10);

    const row = assertNoError(
      await client
        .from('api_keys')
        .insert({
          user_id: userId,
          name: dto.name,
          key_prefix: prefix,
          key_hash: keyHash,
        })
        .select('id, name, key_prefix, created_at')
        .single(),
    );

    return { ...row, key: raw };
  }

  async revoke(token: string, userId: string, id: string) {
    const client = this.supabase.createClient(token);
    await client
      .from('api_keys')
      .update({ revoked_at: new Date().toISOString() })
      .eq('id', id)
      .eq('user_id', userId);
  }

  async validateRawKey(rawKey: string): Promise<{ userId: string; keyId: string } | null> {
    if (!rawKey.startsWith('ol_')) return null;
    const keyHash = createHash('sha256').update(rawKey).digest('hex');
    const client = this.supabase.serviceRole();
    const row = assertNoError(
      await client
        .from('api_keys')
        .select('id, user_id')
        .eq('key_hash', keyHash)
        .is('revoked_at', null)
        .maybeSingle(),
    );
    if (!row) return null;

    await client
      .from('api_keys')
      .update({ last_used_at: new Date().toISOString() })
      .eq('id', row.id);

    return { userId: row.user_id as string, keyId: row.id as string };
  }
}
