import { InternalServerErrorException } from '@nestjs/common';
import { GdprService } from './gdpr.service';
import { SupabaseService } from '../database/supabase.service';
import { R2Service } from '../storage/r2.service';

/**
 * Regression tests for the GDPR erasure correctness fix (phase 3):
 *  - throw (not return ok:true) when auth.admin.deleteUser fails
 *  - enumerate residual iNaturalist observation ids
 */
describe('GdprService.eraseUser', () => {
  const buildSupabase = (opts: {
    authError?: { message: string } | null;
    inatIds?: Array<{ inat_observation_id: number | null }>;
  }) => {
    // iNat residual enumeration now reads inaturalist_push_queue with two
    // chained .eq() filters (user_id, status='sent') then a .not(is null).
    const pushQueueQuery = {
      select: jest.fn().mockReturnThis(),
      eq: jest.fn().mockReturnThis(),
      not: jest.fn().mockResolvedValue({ data: opts.inatIds ?? [], error: null }),
    };
    const admin = {
      rpc: jest.fn().mockResolvedValue({ data: null, error: null }),
      from: jest.fn().mockReturnValue(pushQueueQuery),
      auth: {
        admin: {
          deleteUser: jest
            .fn()
            .mockResolvedValue({ error: opts.authError ?? null }),
        },
      },
    };
    return { serviceRole: jest.fn().mockReturnValue(admin) } as unknown as SupabaseService;
  };

  const r2 = {
    deletePrefix: jest.fn().mockResolvedValue(0),
  } as unknown as R2Service;

  it('throws when the canonical auth delete fails', async () => {
    const supabase = buildSupabase({ authError: { message: 'boom' } });
    const service = new GdprService(supabase, r2);
    await expect(
      service.eraseUser('user-1', 'user-1', false, 'DELETE MY ACCOUNT'),
    ).rejects.toThrow(InternalServerErrorException);
  });

  it('returns residual iNat observation ids on success', async () => {
    const supabase = buildSupabase({
      authError: null,
      inatIds: [{ inat_observation_id: 111 }, { inat_observation_id: 222 }],
    });
    const service = new GdprService(supabase, r2);
    const result = await service.eraseUser(
      'user-1',
      'user-1',
      false,
      'DELETE MY ACCOUNT',
    );
    expect(result.ok).toBe(true);
    expect(result.auth_deleted).toBe(true);
    expect(result.inat_observations).toEqual([111, 222]);
  });
});
