import { registerAs } from '@nestjs/config';

export interface SupabaseConfig {
  url: string;
  anonKey: string;
  serviceRoleKey: string;
}

export default registerAs(
  'supabase',
  (): SupabaseConfig => ({
    url: process.env['SUPABASE_URL'] ?? '',
    anonKey:
      process.env['SUPABASE_ANON_KEY'] ??
      process.env['SUPABASE_PUBLISHABLE_KEY'] ??
      '',
    serviceRoleKey:
      process.env['SUPABASE_SERVICE_ROLE_KEY'] ??
      process.env['SUPABASE_SECRET_KEY'] ??
      '',
  }),
);
