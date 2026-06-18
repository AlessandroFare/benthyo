import { SetMetadata } from '@nestjs/common';

/**
 * Decorator for the @TaxonomyExpertGuard. Marks a route as requiring the
 * calling user to have users.taxonomy_expert = true. Operator admins are
 * not sufficient for this gate.
 */
export const TAXONOMY_EXPERT_KEY = 'requiresTaxonomyExpert';
export const RequiresTaxonomyExpert = () =>
  SetMetadata(TAXONOMY_EXPERT_KEY, true);
