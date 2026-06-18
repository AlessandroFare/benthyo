import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { OperatorRole } from '../../database/database.types';
import { SupabaseService } from '../../database/supabase.service';
import { OPERATOR_ROLES_KEY } from '../decorators/operator-roles.decorator';
import { AuthenticatedRequest } from '../types/request.interface';
import { assertNoError } from '../utils/supabase-error.util';

@Injectable()
export class OperatorRoleGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly supabase: SupabaseService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const requiredRoles = this.reflector.getAllAndOverride<OperatorRole[]>(
      OPERATOR_ROLES_KEY,
      [context.getHandler(), context.getClass()],
    );

    if (!requiredRoles?.length) {
      return true;
    }

    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const operatorId =
      request.params['operatorId'] ?? request.params['id'] ?? request.body?.operator_id;

    if (!operatorId) {
      throw new ForbiddenException('Operator context is required');
    }

    const client = this.supabase.createClient(request.accessToken);
    const membership = assertNoError(
      await client
        .from('operator_users')
        .select('role')
        .eq('operator_id', operatorId)
        .eq('user_id', request.user.id)
        .maybeSingle(),
    );

    if (!membership || !requiredRoles.includes(membership.role as OperatorRole)) {
      throw new ForbiddenException('Insufficient operator permissions');
    }

    return true;
  }
}
