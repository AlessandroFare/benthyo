import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  SetMetadata,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { SupabaseService } from '../../database/supabase.service';
import { assertNoError } from '../utils/supabase-error.util';
import { AuthenticatedRequest } from '../types/request.interface';

export type Tier = 'free' | 'starter' | 'pro';
export const REQUIRED_TIER_KEY = 'requiredTier';

/**
 * Decorator. Apply on a route handler to require a minimum subscription
 * tier. The decorator alone is not enough — the route handler must also
 * be operating on the caller's own operator (the guard resolves the
 * operator from the URL :operatorId or from the caller's operator_users
 * membership, in that order).
 */
export const RequireTier = (tier: Tier) => SetMetadata(REQUIRED_TIER_KEY, tier);

const TIER_ORDER: Record<Tier, number> = { free: 0, starter: 1, pro: 2 };

@Injectable()
export class TierGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly supabase: SupabaseService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const required = this.reflector.getAllAndOverride<Tier>(REQUIRED_TIER_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!required) return true;

    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    if (!request.user?.id || !request.accessToken) {
      throw new ForbiddenException('Authentication required');
    }

    // Resolve the operator this request concerns.
    const operatorId =
      (request.params?.operatorId as string | undefined) ??
      (request.params?.id as string | undefined) ??
      (request.body?.operator_id as string | undefined);

    const client = this.supabase.createClient(request.accessToken);

    // If no operatorId is in the URL, use the caller's primary operator.
    let opId = operatorId;
    if (!opId) {
      const mine = assertNoError(
        await client
          .from('operator_users')
          .select('operator_id, role')
          .eq('user_id', request.user.id)
          .order('invited_at', { ascending: true })
          .limit(1)
          .maybeSingle(),
      );
      if (!mine) {
        throw new ForbiddenException('No operator associated with this account');
      }
      opId = mine.operator_id as string;
    }

    const op = assertNoError(
      await client
        .from('operators')
        .select('subscription_tier, subscription_status, updated_at')
        .eq('id', opId)
        .maybeSingle(),
    );
    if (!op) throw new ForbiddenException('Operator not found');

    const status = op.subscription_status as string;
    // Grace period: past_due operators keep access for 14 days after the
    // last update, then downgrade to read-only.
    const updatedAt = new Date(op.updated_at as string).getTime();
    const graceMs = 14 * 24 * 60 * 60 * 1000;
    const isActive =
      status === 'active' ||
      status === 'trialing' ||
      (status === 'past_due' && Date.now() - updatedAt < graceMs);

    if (!isActive) {
      throw new ForbiddenException('Subscription is past due or canceled');
    }

    const current = (op.subscription_tier ?? 'free') as Tier;
    if (TIER_ORDER[current] < TIER_ORDER[required]) {
      throw new ForbiddenException(
        `This feature requires the ${required} tier (current: ${current})`,
      );
    }

    return true;
  }
}
