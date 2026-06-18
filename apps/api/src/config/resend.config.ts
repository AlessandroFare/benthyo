import { registerAs } from '@nestjs/config';

export interface ResendConfig {
  apiKey: string;
  fromEmail: string;
  fromName: string;
}

export default registerAs(
  'resend',
  (): ResendConfig => ({
    apiKey: process.env['RESEND_API_KEY'] ?? '',
    fromEmail: process.env['RESEND_FROM_EMAIL'] ?? 'hello@oceanlog.app',
    fromName: process.env['RESEND_FROM_NAME'] ?? 'OceanLog',
  }),
);
