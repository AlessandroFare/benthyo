import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ApiKeysService } from '../../api-keys/api-keys.service';
import { SupabaseService } from '../../database/supabase.service';
import { AuthenticatedRequest } from '../types/request.interface';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly supabase: SupabaseService,
    private readonly reflector: Reflector,
    private readonly apiKeys: ApiKeysService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) {
      return true;
    }

    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const authHeader = request.headers.authorization;
    const apiKeyHeader = request.headers['x-api-key'] as string | undefined;

    if (authHeader?.startsWith('Bearer ')) {
      const token = authHeader.slice(7).trim();
      if (!token) {
        throw new UnauthorizedException('Missing access token');
      }

      const client = this.supabase.anonClient();
      const { data, error } = await client.auth.getUser(token);

      if (error || !data.user) {
        throw new UnauthorizedException('Invalid or expired token');
      }

      request.user = {
        id: data.user.id,
        email: data.user.email,
        role: data.user.role,
      };
      request.accessToken = token;
      return true;
    }

    const rawKey = apiKeyHeader?.trim();
    if (rawKey) {
      const validated = await this.apiKeys.validateRawKey(rawKey);
      if (!validated) {
        throw new UnauthorizedException('Invalid API key');
      }
      request.user = { id: validated.userId, email: undefined, role: 'authenticated' };
      request.accessToken = '';
      return true;
    }

    throw new UnauthorizedException('Missing Authorization header or X-Api-Key');
  }
}
