import {
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser, AccessToken } from '../common/decorators/current-user.decorator';
import { AuthUser } from '../common/types/auth-user.interface';
import { SupabaseService } from '../database/supabase.service';
import { assertNoError } from '../common/utils/supabase-error.util';

/**
 * Sync queue / dead-letter endpoints.
 *
 * When a write fails on the client (network drop, 5xx, conflict) the
 * Flutter sync manager parks the payload in the `dead_letter` table
 * and surfaces it on the settings screen. These endpoints let the
 * user inspect, retry, and dismiss those parked items.
 *
 * Routes:
 *   GET    /v1/sync/dead-letter       — list this user's parked items
 *   POST   /v1/sync/dead-letter/:id/retry  — re-send the payload
 *   DELETE /v1/sync/dead-letter/:id   — dismiss an item (no retry)
 *   POST   /v1/sync/dead-letter/retry-all  — retry every parked item
 *   DELETE /v1/sync/dead-letter       — dismiss everything
 */
@ApiTags('sync')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('sync/dead-letter')
export class SyncDeadLetterController {
  constructor(private readonly supabase: SupabaseService) {}

  @Get()
  @ApiOperation({ summary: 'List the caller\u2019s parked (failed-sync) items' })
  async list(@CurrentUser() user: AuthUser, @AccessToken() token: string) {
    const client = this.supabase.createClient(token);
    return assertNoError(
      await client
        .from('dead_letter')
        .select('*')
        .eq('user_id', user.id)
        .is('dismissed_at', null)
        .order('last_failed_at', { ascending: false }),
    );
  }

  @Post(':id/retry')
  @ApiOperation({ summary: 'Re-send a single parked payload' })
  async retryOne(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id', new ParseUUIDPipe()) id: string,
  ): Promise<{ retried: true; status: number }> {
    const client = this.supabase.createClient(token);

    // Pull the parked row through the RLS-aware client (so we know it
    // belongs to this user).
    const row = (assertNoError(
      await client
        .from('dead_letter')
        .select('*')
        .eq('id', id)
        .eq('user_id', user.id)
        .maybeSingle(),
    ) as {
      endpoint: string;
      payload: Record<string, unknown>;
      client_request_id: string | null;
    } | null);
    if (!row) {
      return { retried: false as unknown as true, status: 404 };
    }

    const url = row.endpoint;
    const { error } = await client.rpc('sync_retry_dead_letter', {
      p_id: id,
    });
    // If the RPC doesn't exist, fall through to a direct fetch via
    // the service role client (the API server makes the call itself
    // when the RPC is missing).
    if (error && error.code === '42883') {
      const admin = this.supabase.serviceRole();
      const res = await fetch(`${process.env['API_BASE_URL'] ?? ''}${url}`, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          authorization: `Bearer ${token}`,
          'x-client-request-id': row.client_request_id ?? crypto.randomUUID(),
        },
        body: JSON.stringify(row.payload),
      });
      if (res.ok) {
        await admin
          .from('dead_letter')
          .update({ retried_at: new Date().toISOString(), attempts: 1 })
          .eq('id', id);
      }
      return { retried: true, status: res.status };
    }
    assertNoError({ data: null, error });
    return { retried: true, status: 200 };
  }

  @Delete(':id')
  @ApiOperation({ summary: 'Dismiss a parked item (no retry)' })
  async dismiss(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
    @Param('id', new ParseUUIDPipe()) id: string,
  ) {
    const client = this.supabase.createClient(token);
    assertNoError(
      await client
        .from('dead_letter')
        .update({ dismissed_at: new Date().toISOString() })
        .eq('id', id)
        .eq('user_id', user.id),
    );
    return { dismissed: true, id };
  }

  @Post('retry-all')
  @ApiOperation({ summary: 'Retry every parked item for the caller' })
  async retryAll(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
  ): Promise<{ attempted: number; succeeded: number }> {
    const client = this.supabase.createClient(token);
    const rows = (assertNoError(
      await client
        .from('dead_letter')
        .select('id')
        .eq('user_id', user.id)
        .is('dismissed_at', null)
        .is('retried_at', null),
    ) as Array<{ id: string }>) ?? [];
    let succeeded = 0;
    for (const r of rows) {
      const result = await this.retryOne(user, token, r.id);
      if (result.status >= 200 && result.status < 300) succeeded += 1;
    }
    return { attempted: rows.length, succeeded };
  }

  @Delete()
  @ApiOperation({ summary: 'Dismiss every parked item for the caller' })
  async dismissAll(
    @CurrentUser() user: AuthUser,
    @AccessToken() token: string,
  ) {
    const client = this.supabase.createClient(token);
    assertNoError(
      await client
        .from('dead_letter')
        .update({ dismissed_at: new Date().toISOString() })
        .eq('user_id', user.id)
        .is('dismissed_at', null),
    );
    return { dismissed_all: true };
  }
}