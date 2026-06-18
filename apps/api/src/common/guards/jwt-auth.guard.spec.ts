import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ApiKeysService } from '../../api-keys/api-keys.service';
import { JwtAuthGuard } from './jwt-auth.guard';
import { SupabaseService } from '../../database/supabase.service';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';

describe('JwtAuthGuard', () => {
  let guard: JwtAuthGuard;
  let supabase: jest.Mocked<Pick<SupabaseService, 'anonClient'>>;
  let reflector: jest.Mocked<Pick<Reflector, 'getAllAndOverride'>>;
  let apiKeys: jest.Mocked<Pick<ApiKeysService, 'validateRawKey'>>;

  const mockContext = (headers: Record<string, string> = {}): ExecutionContext =>
    ({
      switchToHttp: () => ({
        getRequest: () => ({
          headers,
        }),
      }),
      getHandler: () => ({}),
      getClass: () => ({}),
    }) as ExecutionContext;

  beforeEach(() => {
    supabase = {
      anonClient: jest.fn().mockReturnValue({
        auth: {
          getUser: jest.fn(),
        },
      }),
    };
    reflector = {
      getAllAndOverride: jest.fn().mockReturnValue(false),
    };
    apiKeys = {
      validateRawKey: jest.fn().mockResolvedValue(null),
    };
    guard = new JwtAuthGuard(
      supabase as unknown as SupabaseService,
      reflector as unknown as Reflector,
      apiKeys as unknown as ApiKeysService,
    );
  });

  it('allows public routes without a token', async () => {
    reflector.getAllAndOverride.mockReturnValue(true);

    await expect(guard.canActivate(mockContext())).resolves.toBe(true);
    expect(supabase.anonClient).not.toHaveBeenCalled();
  });

  it('rejects requests without Authorization header', async () => {
    await expect(guard.canActivate(mockContext())).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('validates bearer token and attaches user to request', async () => {
    const request = { headers: { authorization: 'Bearer valid-token' } };
    const context = {
      switchToHttp: () => ({ getRequest: () => request }),
      getHandler: () => ({}),
      getClass: () => ({}),
    } as ExecutionContext;

    const getUser = jest.fn().mockResolvedValue({
      data: { user: { id: 'user-1', email: 'a@b.com', role: 'authenticated' } },
      error: null,
    });
    supabase.anonClient.mockReturnValue({ auth: { getUser } } as never);

    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(getUser).toHaveBeenCalledWith('valid-token');
    expect(request).toMatchObject({
      user: { id: 'user-1', email: 'a@b.com', role: 'authenticated' },
      accessToken: 'valid-token',
    });
  });

  it('rejects invalid tokens', async () => {
    const context = mockContext({ authorization: 'Bearer bad-token' });
    supabase.anonClient.mockReturnValue({
      auth: {
        getUser: jest.fn().mockResolvedValue({ data: { user: null }, error: new Error('bad') }),
      },
    } as never);

    await expect(guard.canActivate(context)).rejects.toThrow(UnauthorizedException);
  });

  it('reads public metadata key', async () => {
    reflector.getAllAndOverride.mockImplementation((key) => key === IS_PUBLIC_KEY);
    await expect(guard.canActivate(mockContext())).resolves.toBe(true);
  });
});
