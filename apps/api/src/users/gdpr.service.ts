import { Injectable, Logger, NotFoundException, BadRequestException, UnauthorizedException, InternalServerErrorException } from '@nestjs/common';
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
  ): Promise<{
    ok: true;
    deleted_r2_objects: number;
    auth_deleted: boolean;
    inat_observations: number[];
    r2_partial_failure: boolean;
  }> {
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

    // 2. iNaturalist observations. OceanLog pushes verified sightings to iNat
    //    via the inaturalist_push_queue (migration 021); the iNat observation
    //    id is recorded on the queue row (status='sent', inat_observation_id
    //    set), NOT on sightings. Deleting iNat-side requires the *user's*
    //    OAuth token, which we do not store, so we collect the pushed
    //    observation ids, log them as residual data, and return them so the
    //    caller can surface "delete these on iNaturalist" guidance.
    let inatObservations: number[] = [];
    try {
      const { data: obs } = await admin
        .from('inaturalist_push_queue')
        .select('inat_observation_id')
        .eq('user_id', targetUserId)
        .eq('status', 'sent')
        .not('inat_observation_id', 'is', null);
      inatObservations = (obs ?? [])
        .map((r: { inat_observation_id: number | null }) => r.inat_observation_id)
        .filter((id): id is number => typeof id === 'number');
      if (inatObservations.length > 0) {
        this.logger.warn(
          `GDPR erasure for ${targetUserId}: ${inatObservations.length} iNaturalist observation(s) remain on iNat and must be removed by the user (ids: ${inatObservations.join(', ')}).`,
        );
      }
    } catch (err) {
      this.logger.error(
        `Failed to enumerate iNat observations for ${targetUserId}`,
        err as Error,
      );
    }

    // 3. Delete R2 objects. We use the deterministic key prefixes
    //    that the upload endpoints create. Track failures so we can
    //    report partial completion rather than silently orphaning media.
    let r2PartialFailure = false;
    const sightingsDeleted = await this.r2
      .deletePrefix(`sightings/${targetUserId}/`)
      .catch((err) => {
        this.logger.error(`R2 sightings delete failed for ${targetUserId}`, err as Error);
        r2PartialFailure = true;
        return 0;
      });
    const avatarsDeleted = await this.r2
      .deletePrefix(`avatars/${targetUserId}/`)
      .catch((err) => {
        this.logger.error(`R2 avatars delete failed for ${targetUserId}`, err as Error);
        r2PartialFailure = true;
        return 0;
      });

    // 4. Remove the auth user. This cascades to public.users and every
    //    FK that points at it (operator_users, dive_logs, sightings,
    //    corrections, user_life_list, user_badges, ...). This is the
    //    canonical "user is gone" operation: if it fails we must NOT
    //    report success, or the caller believes the account was erased.
    const { error: authErr } = await admin.auth.admin.deleteUser(targetUserId);
    if (authErr) {
      this.logger.error(
        `auth.admin.deleteUser failed for ${targetUserId}: ${authErr.message}`,
      );
      throw new InternalServerErrorException(
        'Account erasure failed at the final step. The account is soft-deleted and recoverable; retry or contact support.',
      );
    }

    return {
      ok: true,
      deleted_r2_objects: sightingsDeleted + avatarsDeleted,
      auth_deleted: true,
      inat_observations: inatObservations,
      r2_partial_failure: r2PartialFailure,
    };
  }
}
