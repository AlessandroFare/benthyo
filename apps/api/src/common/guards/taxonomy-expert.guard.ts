import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { SupabaseService } from '../../database/supabase.service';
import { assertNoError } from '../utils/supabase-error.util';
import { AuthenticatedRequest } from '../types/request.interface';

export const TAXONOMY_EXPERT_KEY = 'requiresTaxonomyExpert';
export const OPERATOR_ADMIN_KEY = 'requiresOperatorAdmin';

/**
 * Guards a route so only:
 *   - users flagged as taxonomy experts (any operator), OR
 *   - operator owners / admins of any operator
 * can proceed. Both groups must prove their role server-side; the JWT
 * does not carry role information.
 *
 * Use either:
 *   @TaxonomyExpert()
 *   @OperatorAdmin()
 * on the route to declare which check applies. Default: require any
 * verifier (taxonomy expert OR operator admin of any operator).
 */
@Injectable()
export class TaxonomyExpertGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly supabase: SupabaseService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const requiresExpert = this.reflector.getAllAndOverride<boolean>(
      TAXONOMY_EXPERT_KEY,
      [context.getHandler(), context.getClass()],
    );
    const requiresAdmin = this.reflector.getAllAndOverride<boolean>(
      OPERATOR_ADMIN_KEY,
      [context.getHandler(), context.getClass()],
    );
    // Default: any verifier is acceptable (expert OR operator admin).
    const mode: 'expert' | 'admin' | 'either' = requiresExpert
      ? 'expert'
      : requiresAdmin
        ? 'admin'
        : 'either';

    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    if (!request.user?.id || !request.accessToken) {
      throw new ForbiddenException('Authentication required');
    }

    const client = this.supabase.createClient(request.accessToken);

    // Read profile via RLS-aware client. The user can only see their own
    // profile row regardless of policy, so this is safe.
    const profile = assertNoError(
      await client
        .from('users')
        .select('taxonomy_expert')
        .eq('id', request.user.id)
        .maybeSingle(),
    );

    if (mode === 'expert') {
      if (!profile?.taxonomy_expert) {
        throw new ForbiddenException('Taxonomy expert role required');
      }
      return true;
    }

    if (mode === 'admin') {
      // Check operator_users for any membership in (owner, admin).
      const membership = assertNoError(
        await client
          .from('operator_users')
          .select('role')
          .eq('user_id', request.user.id)
          .in('role', ['owner', 'admin'])
          .limit(1)
          .maybeSingle(),
      );
      if (!membership) {
        throw new ForbiddenException('Operator admin role required');
      }
      return true;
    }

    // 'either' — accept any verifier.
    if (profile?.taxonomy_expert) return true;
    const membership = assertNoError(
      await client
        .from('operator_users')
        .select('role')
        .eq('user_id', request.user.id)
        .in('role', ['owner', 'admin'])
        .limit(1)
        .maybeSingle(),
    );
    if (membership) return true;

    throw new ForbiddenException('Verifier role required (taxonomy expert or operator admin)');
  }
}

export const TaxonomyExpert = () =>
  Reflect.metadata(TAXONOMY_EXPERT_KEY, true);

export const OperatorAdmin = () =>
  Reflect.metadata(OPERATOR_ADMIN_KEY, true);
