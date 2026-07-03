import { ForbiddenException } from '@nestjs/common';
import { OperatorsService } from './operators.service';
import { SupabaseService } from '../database/supabase.service';

/**
 * Regression tests for server-side tier-limit enforcement (phase 6).
 * Free tier: 3 sites, 1 team member. We assert the service throws 403
 * when the live count is at/over the cap and inserts otherwise.
 */
describe('OperatorsService tier limits', () => {
  let service: OperatorsService;
  let supabase: jest.Mocked<Pick<SupabaseService, 'createClient'>>;

  // Build a client whose operators.maybeSingle() returns the given tier
  // and whose count query returns the given count. The insert path
  // resolves to a created row.
  const buildClient = (tier: string, count: number) => {
    const operatorsBuilder = {
      select: jest.fn().mockReturnThis(),
      eq: jest.fn().mockReturnThis(),
      maybeSingle: jest.fn().mockResolvedValue({
        data: { subscription_tier: tier },
        error: null,
      }),
    };
    const countBuilder = {
      select: jest.fn().mockReturnThis(),
      eq: jest.fn().mockResolvedValue({ count, error: null }),
    };
    const insertBuilder = {
      insert: jest.fn().mockReturnThis(),
      select: jest.fn().mockReturnThis(),
      single: jest.fn().mockResolvedValue({ data: { id: 'row-1' }, error: null }),
    };
    return {
      from: jest.fn((table: string) => {
        if (table === 'operators') return operatorsBuilder;
        // The count query and the insert query both hit the resource
        // table; differentiate by whether `.insert` is called. We hand
        // back a merged builder so either chain resolves.
        return { ...countBuilder, ...insertBuilder };
      }),
    };
  };

  beforeEach(() => {
    supabase = { createClient: jest.fn() };
    service = new OperatorsService(supabase as unknown as SupabaseService);
  });

  it('rejects linking a 4th site on the free tier (cap 3)', async () => {
    supabase.createClient.mockReturnValue(buildClient('free', 3) as never);
    await expect(
      service.linkSite('token', 'op-1', { dive_site_id: 'site-x', is_primary: false }),
    ).rejects.toThrow(ForbiddenException);
  });

  it('allows linking a site under the free cap', async () => {
    supabase.createClient.mockReturnValue(buildClient('free', 2) as never);
    const row = await service.linkSite('token', 'op-1', {
      dive_site_id: 'site-x',
      is_primary: false,
    });
    expect(row).toEqual({ id: 'row-1' });
  });

  it('rejects inviting a 2nd member on the free tier (team cap 1)', async () => {
    supabase.createClient.mockReturnValue(buildClient('free', 1) as never);
    await expect(
      service.inviteMember('token', 'op-1', { user_id: 'u-2', role: 'staff' } as never),
    ).rejects.toThrow(ForbiddenException);
  });

  it('allows a pro operator to add many sites (cap 100)', async () => {
    supabase.createClient.mockReturnValue(buildClient('pro', 42) as never);
    const row = await service.linkSite('token', 'op-1', {
      dive_site_id: 'site-x',
      is_primary: false,
    });
    expect(row).toEqual({ id: 'row-1' });
  });
});
