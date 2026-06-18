import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  InternalServerErrorException,
  NotFoundException,
} from '@nestjs/common';
import { PostgrestError } from '@supabase/supabase-js';

/**
 * Map a Supabase/Postgrest error to the right HTTP exception. This is
 * the single place where the PostgREST error vocabulary is translated
 * into Nest exceptions.
 */
export function mapSupabaseError(error: PostgrestError): never {
  const message = error?.message ?? 'Database error';
  const code = error?.code ?? '';

  if (code === 'PGRST116' || message.includes('0 rows')) {
    throw new NotFoundException(message);
  }
  if (code === '23505') {
    throw new ConflictException(message);
  }
  if (code === '42501' || code === 'PGRST301') {
    throw new ForbiddenException(message);
  }
  if (code.startsWith('22') || code.startsWith('23')) {
    throw new BadRequestException(message);
  }

  throw new InternalServerErrorException(message);
}

/**
 * Check that the result has no error and return the data payload.
 * Generic over the shape of the data field so it can be used with
 * `.select(...)`, `.rpc(...)`, `.update(...)`, etc.
 */
export function assertNoError<T>(result: { data: T; error: PostgrestError | null }): T {
  if (result.error) {
    mapSupabaseError(result.error);
  }
  return result.data as T;
}

/**
 * Convenience: when the result has a `count` field too (e.g. after a
 * `.select('*', { count: 'exact' })`).
 */
export function assertNoErrorWithCount<T>(result: {
  data: T;
  error: PostgrestError | null;
  count: number | null;
}): T {
  if (result.error) {
    mapSupabaseError(result.error);
  }
  return result.data as T;
}
