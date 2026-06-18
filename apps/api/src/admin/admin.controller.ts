import { Controller, Delete, Get, Param, Post, Query } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiQuery,
  ApiTags,
} from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';

/**
 * Admin / owner soft-delete + restore + list.
 *
 * Routes:
 *   POST   /v1/admin/soft-delete            — soft-delete a row
 *   POST   /v1/admin/restore                — restore a soft-deleted row
 *   GET    /v1/admin/deleted/:table         — list soft-deleted rows
 *   DELETE /v1/admin/purge/:table/:id       — hard-delete (irreversible)
 *   POST   /v1/admin/purge/prune            — run the scheduled prune job
 *
 * The RLS policies on the underlying tables will not let the caller's
 * JWT touch deleted_at, so all writes go through the SECURITY DEFINER
 * functions defined in migration 033.
 */
@ApiTags('admin')
@ApiBearerAuth()
@Controller('admin')
@Throttle({ default: { limit: 20, ttl: 60_000 } })
export class AdminController {
  constructor(private readonly supabase: SupabaseService) {}

  @Post('soft-delete')
  @ApiOperation({
    summary: 'Soft-delete a row (owner-or-admin). Pairs with migration 033 RPC.',
  })
  async softDelete(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Query('table') table: string,
    @Query('id') id: string,
    @Query('reason') reason?: string,
  ) {
    // Use the caller's JWT to hit the RPC; auth.uid() is captured inside.
    const client = this.supabase.createClient(token);
    const { error } = await client.rpc('soft_delete_row', {
      p_table: table,
      p_id: id,
      p_reason: reason ?? null,
    });
    assertNoError({ data: null, error });
    return { ok: true, table, id, actor: user.id };
  }

  @Post('restore')
  @ApiOperation({ summary: 'Restore a soft-deleted row (admin only).' })
  async restore(
    @AccessToken() token: string,
    @Query('table') table: string,
    @Query('id') id: string,
  ) {
    const client = this.supabase.createClient(token);
    const { error } = await client.rpc('restore_soft_deleted', {
      p_table: table,
      p_id: id,
    });
    assertNoError({ data: null, error });
    return { ok: true, table, id };
  }

  @Get('deleted/:table')
  @ApiOperation({ summary: 'List soft-deleted rows (admin only).' })
  @ApiQuery({ name: 'limit', required: false, type: Number })
  async listDeleted(
    @AccessToken() token: string,
    @Param('table') table: string,
    @Query('limit') limit?: number,
  ) {
    const client = this.supabase.createClient(token);
    const { data, error } = await client.rpc('list_soft_deleted', {
      p_table: table,
      p_limit: limit ?? 50,
    });
    return assertNoError({ data, error });
  }

  @Delete('purge/:table/:id')
  @ApiOperation({ summary: 'Hard-delete a soft-deleted row (admin only).' })
  async purge(
    @AccessToken() token: string,
    @Param('table') table: string,
    @Param('id') id: string,
  ) {
    const admin = this.supabase.serviceRole();
    const { error } = await admin
      .from(table)
      .delete()
      .eq('id', id)
      .not('deleted_at', 'is', null);
    assertNoError({ data: null, error });
    return { ok: true, table, id };
  }

  @Post('purge/prune')
  @ApiOperation({ summary: 'Run the scheduled prune_soft_deleted() job (admin only).' })
  async prune(
    @Query('retention_days') retentionDays?: number,
    @Query('dry_run') dryRun?: string,
  ) {
    // Service role only — there is no public path to this RPC.
    const admin = this.supabase.serviceRole();
    const { data, error } = await admin.rpc('prune_soft_deleted', {
      p_retention_days: retentionDays ?? 30,
      p_dry_run: dryRun === 'true',
    });
    return assertNoError({ data, error });
  }

  // ----------------------------------------------------------------
  // Marketplace moderation (DD-1.3).
  // ----------------------------------------------------------------

  @Get('marketplace/pending')
  @ApiOperation({ summary: 'List marketplace listings awaiting approval' })
  async listPendingMarketplace() {
    const admin = this.supabase.serviceRole();
    return assertNoError(
      await admin
        .from('operator_marketplace_listings')
        .select('*, operator:operators(id, name, slug)')
        .eq('is_approved', false)
        .eq('is_active', true)
        .order('created_at', { ascending: false }),
    );
  }

  @Post('marketplace/:id/approve')
  @ApiOperation({ summary: 'Approve a marketplace listing for public visibility' })
  async approveMarketplace(@Param('id') id: string) {
    const admin = this.supabase.serviceRole();
    assertNoError(
      await admin.rpc('approve_marketplace_listing', { p_id: id }),
    );
    return { approved: true, id };
  }
}
