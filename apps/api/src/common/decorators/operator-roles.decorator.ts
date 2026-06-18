import { SetMetadata } from '@nestjs/common';
import { OperatorRole } from '../../database/database.types';

export const OPERATOR_ROLES_KEY = 'operatorRoles';

export const OperatorRoles = (...roles: OperatorRole[]) =>
  SetMetadata(OPERATOR_ROLES_KEY, roles);
