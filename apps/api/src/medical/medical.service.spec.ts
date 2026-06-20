import { MedicalService } from './medical.service';
import { SupabaseService } from '../database/supabase.service';
import { ConfigService } from '@nestjs/config';

/**
 * Regression test for the CRITICAL medical-key fix (phase 2). The service
 * must thread the env master key + salt through the *_v2 RPCs so the DB
 * encrypts under the real key, not the public dev placeholder.
 */
describe('MedicalService key threading', () => {
  const makeConfig = (vals: Record<string, string | undefined>) =>
    ({ get: (k: string) => vals[k] }) as unknown as ConfigService;

  it('submit() calls submit_medical_form_v2 with the env key + salt', async () => {
    const rpc = jest.fn().mockResolvedValue({ data: { id: 's-1' }, error: null });
    const maybeSingle = jest
      .fn()
      .mockResolvedValue({ data: { id: 'tpl-1' }, error: null });
    const client = {
      from: jest.fn().mockReturnValue({
        select: jest.fn().mockReturnThis(),
        eq: jest.fn().mockReturnThis(),
        maybeSingle,
      }),
      rpc,
    };
    const supabase = {
      createClient: jest.fn().mockReturnValue(client),
    } as unknown as SupabaseService;
    const config = makeConfig({
      MEDICAL_ENCRYPTION_MASTER_KEY: 'real-master-key',
      MEDICAL_ENCRYPTION_KEY_SALT: 'real-salt',
    });
    const service = new MedicalService(supabase, config);

    await service.submit('token', 'user-1', {
      template_id: 'tpl-1',
      operator_id: 'op-1',
      answers: [{ id: 'q1', value: 'no' }],
      signer_name: 'Jane Diver',
    } as never);

    expect(rpc).toHaveBeenCalledWith(
      'submit_medical_form_v2',
      expect.objectContaining({
        p_master_key: 'real-master-key',
        p_salt: 'real-salt',
        p_user_id: 'user-1',
        p_operator_id: 'op-1',
      }),
    );
  });

  it('mySubmissions() calls the _v2 decrypt RPC with the env key', async () => {
    const rpc = jest.fn().mockResolvedValue({ data: [], error: null });
    const supabase = {
      createClient: jest.fn().mockReturnValue({ rpc }),
    } as unknown as SupabaseService;
    const config = makeConfig({
      MEDICAL_ENCRYPTION_MASTER_KEY: 'real-master-key',
      MEDICAL_ENCRYPTION_KEY_SALT: 'real-salt',
    });
    const service = new MedicalService(supabase, config);

    await service.mySubmissions('token', 'user-1');

    expect(rpc).toHaveBeenCalledWith(
      'my_medical_submissions_decrypted_v2',
      expect.objectContaining({
        p_user_id: 'user-1',
        p_master_key: 'real-master-key',
        p_salt: 'real-salt',
      }),
    );
  });

  it('fail-fasts at boot in production when the master key is unset', async () => {
    const supabase = {} as unknown as SupabaseService;
    const config = makeConfig({ NODE_ENV: 'production' });
    const service = new MedicalService(supabase, config);
    await expect(service.onModuleInit()).rejects.toThrow(
      /MEDICAL_ENCRYPTION_MASTER_KEY/,
    );
  });
});
