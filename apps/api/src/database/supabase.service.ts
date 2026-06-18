import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { SupabaseConfig } from '../config/supabase.config';

/**
 * Factory for Supabase clients.
 *
 * `createClient(accessToken)` returns an RLS-aware client that executes
 * Postgres policies as the calling user. Always prefer this for
 * per-request CRUD.
 *
 * `serviceRole()` returns a privileged client that bypasses RLS. It is
 * reserved for trusted server operations (cron exports, admin
 * analytics, post-upload confirmation hooks). NEVER pass user data
 * through this client without explicit `eq('user_id', userId)` scoping.
 *
 * The previous version of this file accepted a `fallbackUserId` second
 * argument and silently returned the service-role client when no token
 * was supplied. That pattern was the root of the H-5 security finding:
 * an X-Api-Key authenticated request set `request.accessToken = ''`,
 * services called `createClient(token, userId)`, the empty string was
 * falsy, the fallback path returned the service role, and RLS was
 * bypassed for the entire request. The fallback is removed.
 */
@Injectable()
export class SupabaseService implements OnModuleInit {
  private readonly logger = new Logger(SupabaseService.name);
  private config!: SupabaseConfig;

  constructor(private readonly configService: ConfigService) {}

  onModuleInit(): void {
    this.config = this.configService.get<SupabaseConfig>('supabase')!;
    if (!this.config.url || !this.config.anonKey || !this.config.serviceRoleKey) {
      // Fail fast in production. In dev we still let it boot so the
      // engineer can iterate on the env file, but warn loudly.
      const env = this.configService.get<string>('NODE_ENV') ?? 'development';
      if (env === 'production') {
        throw new Error('Supabase URL/keys are not configured for production');
      }
      this.logger.warn('Supabase URL/keys are not fully configured');
    }
  }

  /**
   * Creates a request-scoped Supabase client authenticated with the user's
   * JWT access token. All queries respect RLS.
   */
  createClient(accessToken: string): SupabaseClient<any, 'public', any> {
    if (!accessToken) {
      throw new Error('Access token is required to create an RLS-aware Supabase client');
    }
    return createClient<any, 'public', any>(this.config.url, this.config.anonKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
      },
      global: {
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
      },
    });
  }

  /**
   * Creates an anonymous/read-only client for public endpoints that do not
   * carry a user token.
   */
  anonClient(): SupabaseClient<any, 'public', any> {
    return createClient<any, 'public', any>(this.config.url, this.config.anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }

  /**
   * Service-role client. Bypasses RLS; must never be exposed to client
   * code. Use only for cron exports, admin analytics, and
   * machine-to-machine flows. ALWAYS scope queries with explicit
   * `eq('user_id', userId)` or equivalent filters.
   */
  serviceRole(): SupabaseClient<any, 'public', any> {
    return createClient<any, 'public', any>(this.config.url, this.config.serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
  }
}
