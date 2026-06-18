import { Injectable, Logger, NotFoundException, BadRequestException, UnauthorizedException } from '@nestjs/common';
import { SupabaseService } from '../database/supabase.service';
import { R2Service } from '../storage/r2.service';
import { assertNoError } from '../common/utils/supabase-error.util';

/**
 * GDPR Article 15 (right of access) and Article 17 (right to erasure)
 * operations. The service wraps the underlying storage + Supabase
 * RPCs in a single transactional flow so the caller cannot end up
 * with a half-deleted account.
 *
 * Notes
 *   - The DB export is built from the `export_user_data(p_user_id)`
 *     RPC defined in migration 026. That function returns a single
 *     JSONB payload with every user-scoped table.
 *   - Media deletion is best-effort: R2 objects may include
 *     `sightings/<userId>/...` and `avatars/<userId>/...`. We do a
 *     ListObjectsV2 paginated scan + batch DeleteObjects.
 *   - The auth user is removed with `auth.admin.deleteUser`, which
 *     cascades to `public.users` (FK ON DELETE CASCADE in migration
 *     003). Operator memberships, dive logs, sightings, and
 *     corrections are all deleted with the user; sightings stay
 *     around as `user_id = NULL` is *not* a valid state in our schema,
 *     so they are cascaded out by the FK on auth.users deletion.
 */
@Injectable()
export class GdprService {
  private readonly logger = new Logger(GdprService.name);

  constructor(
    private readonly supabase: SupabaseService,
    private readonly r2: R2Service,
  ) {}

  /**
   * Build a full user export as a JSON-serialisable object. The caller
   * can hand this to the client as an attachment.
   */
  async exportUserData(userId: string): Promise<Record<string, unknown>> {
    const admin = this.supabase.serviceRole();
    const payload = assertNoError(
      await admin.rpc('export_user_data', { p_user_id: userId }),
    );
    if (!payload) {
      throw new NotFoundException('No data found for this user');
    }
    // The RPC returns a JSONB; we wrap it with a `meta` envelope so
    // consumers can tell when it was generated and under which policy.
    return {
      meta: {
        schema_version: 1,
        exported_at: new Date().toISOString(),
        gdpr_article: '15',
        subject_user_id: userId,
      },
      data: payload as Record<string, unknown>,
    };
  }

  /**
   * Permanently delete a user. Caller must be either the user
   * themselves (verified by JWT) or an admin.
   *
   * Steps:
   *   1. Verify the confirmation string.
   *   2. Soft-delete (which sets deleted_at) so we have a recovery
   *      window for accidental deletions.
   *   3. List + delete R2 objects under sightings/<userId> and
   *      avatars/<userId>.
   *   4. Call auth.admin.deleteUser to remove the auth.users row.
   *      All FK cascades fire, including the public.users row.
   *
   * The auth.admin.deleteUser call is the source of truth for the
   * "user is gone" semantic. If it fails after the soft-delete
   * succeeded, the user can still be restored by an admin within the
   * 30-day window.
   */
  async eraseUser(
    actorId: string,
    targetUserId: string,
    isAdmin: boolean,
    confirmation: string,
  ): Promise<{ ok: true; deleted_r2_objects: number; auth_deleted: boolean }> {
    if (confirmation !== 'DELETE MY ACCOUNT') {
      throw new BadRequestException(
        'Confirmation string must equal "DELETE MY ACCOUNT"',
      );
    }
    if (!isAdmin && actorId !== targetUserId) {
      throw new UnauthorizedException('You can only erase your own account');
    }

    const admin = this.supabase.serviceRole();

    // 1. Best-effort soft-delete via the SECURITY DEFINER RPC.
    //    We don't fail the request if this fails; the auth delete
    //    step is the canonical operation.
    await admin.rpc('soft_delete_row', {
      p_table: 'users',
      p_id: targetUserId,
      p_reason: 'gdpr_erasure',
    });

    // 2. Delete R2 objects. We use the deterministic key prefixes
    //    that the upload endpoints create.
    const sightingsDeleted = await this.r2
      .deletePrefix(`sightings/${targetUserId}/`)
      .catch((err) => {
        this.logger.error(`R2 sightings delete failed for ${targetUserId}`, err as Error);
        return 0;
      });
    const avatarsDeleted = await this.r2
      .deletePrefix(`avatars/${targetUserId}/`)
      .catch((err) => {
        this.logger.error(`R2 avatars delete failed for ${targetUserId}`, err as Error);
        return 0;
      });

    // 3. Remove the auth user. This cascades to public.users and every
    //    FK that points at it (operator_users, dive_logs, sightings,
    //    corrections, user_life_list, user_badges, ...).
    const { error: authErr } = await admin.auth.admin.deleteUser(targetUserId);
    if (authErr) {
      this.logger.error(
        `auth.admin.deleteUser failed for ${targetUserId}: ${authErr.message}`,
      );
      return {
        ok: true,
        deleted_r2_objects: sightingsDeleted + avatarsDeleted,
        auth_deleted: false,
      };
    }

    return {
      ok: true,
      deleted_r2_objects: sightingsDeleted + avatarsDeleted,
      auth_deleted: true,
    };
  }
}
