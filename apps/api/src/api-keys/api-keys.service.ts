import { Injectable } from '@nestjs/common';
import { createHash, pbkdf2Sync, randomBytes, timingSafeEqual } from 'crypto';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';
import { CreateApiKeyDto } from '../medical/dto/medical.dto';

const PBKDF2_ITERATIONS = 100_000;
const PBKDF2_DIGEST = 'sha512';

function hashApiKey(raw: string): string {
  const salt = randomBytes(16).toString('hex');
  const derived = pbkdf2Sync(raw, salt, PBKDF2_ITERATIONS, 64, PBKDF2_DIGEST);
  return `pbkdf2$${PBKDF2_ITERATIONS}$${salt}$${derived.toString('hex')}`;
}

function verifyApiKeyHash(raw: string, stored: string): boolean {
  if (stored.startsWith('pbkdf2$')) {
    const parts = stored.split('$');
    if (parts.length !== 4) return false;
    const iterations = Number.parseInt(parts[1] ?? '', 10);
    const salt = parts[2] ?? '';
    const expectedHex = parts[3] ?? '';
    if (!Number.isFinite(iterations) || !salt || !expectedHex) return false;
    const derived = pbkdf2Sync(raw, salt, iterations, 64, PBKDF2_DIGEST);
    const expected = Buffer.from(expectedHex, 'hex');
    if (expected.length !== derived.length) return false;
    return timingSafeEqual(expected, derived);
  }
  const legacy = createHash('sha256').update(raw).digest('hex');
  return legacy === stored;
}

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
    const keyHash = hashApiKey(raw);
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
    const client = this.supabase.serviceRole();
    const prefix = rawKey.slice(0, 10);
    const candidates = assertNoError(
      await client
        .from('api_keys')
        .select('id, user_id, key_hash')
        .eq('key_prefix', prefix)
        .is('revoked_at', null),
    );
    const row = (candidates ?? []).find((candidate) =>
      verifyApiKeyHash(rawKey, candidate.key_hash as string),
    );
    if (!row) return null;

    await client
      .from('api_keys')
      .update({ last_used_at: new Date().toISOString() })
      .eq('id', row.id);

    return { userId: row.user_id as string, keyId: row.id as string };
  }
}
