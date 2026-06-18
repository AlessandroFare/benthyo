import {
  Controller,
  Get,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { SkipThrottle } from '@nestjs/throttler';
import { Public } from '../common/decorators/public.decorator';
import { SupabaseService } from '../database/supabase.service';

/**
 * Liveness + readiness probes for Railway / Cloud Run / Docker
 * orchestrators. The /health route is mounted at the root (no
 * `/api/v1` prefix) per ADR-012 so the load balancer can probe it
 * without auth and without the API prefix.
 *
 * The throttler is skipped for these endpoints because the load
 * balancer hits them once per second per instance.
 */
@ApiTags('health')
@Controller({ path: '/', version: undefined })
@SkipThrottle()
export class HealthController {
  constructor(private readonly supabase: SupabaseService) {}

  @Public()
  @Get('health')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Liveness probe' })
  health() {
    return {
      status: 'ok',
      service: 'oceanlog-api',
      version: process.env['npm_package_version'] ?? '0.0.0',
      timestamp: new Date().toISOString(),
    };
  }

  @Public()
  @Get('ready')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Readiness probe — verifies Supabase connectivity' })
  async ready() {
    const startedAt = Date.now();
    const client = this.supabase.anonClient();
    const { error } = await client.from('species').select('id').limit(1);
    const dbOk = !error;
    const elapsedMs = Date.now() - startedAt;
    const isReady = dbOk;
    return {
      status: isReady ? 'ok' : 'degraded',
      checks: {
        database: dbOk ? 'ok' : 'error',
      },
      latency_ms: elapsedMs,
      timestamp: new Date().toISOString(),
    };
  }
}
