import { ValidationPipe, RequestMethod } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import * as Sentry from '@sentry/nestjs';
import { AppModule } from './app.module';

async function bootstrap(): Promise<void> {
  const nodeEnv = process.env['NODE_ENV'] ?? 'development';

  if (process.env['SENTRY_DSN']) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const integrations: any[] = [];
    if (process.env['SENTRY_ENABLE_PROFILING'] === 'true') {
      try {
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        const { nodeProfilingIntegration } = require('@sentry/profiling-node');
        integrations.push(nodeProfilingIntegration());
      } catch {
        // Native profiler binary may be missing (e.g. Node 24 on Windows).
      }
    }
    Sentry.init({
      dsn: process.env['SENTRY_DSN'],
      environment: nodeEnv,
      integrations,
      // H-11: 10% sampling exhausts the Sentry free tier on day 1. The
      // sample rate is configurable but defaults to 1% to keep us safely
      // under the 5K-events/month cap.
      tracesSampleRate: Number(process.env['SENTRY_TRACES_SAMPLE_RATE'] ?? 0.01),
      profilesSampleRate: Number(process.env['SENTRY_PROFILES_SAMPLE_RATE'] ?? 0.01),
    });
  }

  const app = await NestFactory.create(AppModule);

  // DD-2.23: CORS hard-fail in production. The previous version fell
  // back to `origin: true` (credentialed CORS reflection) when neither
  // CORS_ORIGIN nor API_CORS_ORIGIN was set, which is a well-known
  // footgun. Production must explicitly opt in to a list of origins.
  const corsOrigin =
    process.env['CORS_ORIGIN']?.split(',') ??
    process.env['API_CORS_ORIGIN']?.split(',');
  if (nodeEnv === 'production' && (!corsOrigin || corsOrigin.length === 0)) {
    throw new Error(
      'CORS_ORIGIN (or API_CORS_ORIGIN) must be set in production',
    );
  }
  app.enableCors({
    origin: corsOrigin ?? true,
    credentials: true,
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: false },
    }),
  );

  app.setGlobalPrefix('api/v1', {
    exclude: [{ path: 'health', method: RequestMethod.GET }, 'ready'],
  });

  const swaggerConfig = new DocumentBuilder()
    .setTitle('OceanLog API')
    .setDescription('Scuba logging, species sightings, and operator analytics')
    .setVersion('1.0')
    .addBearerAuth()
    .build();

  const document = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('api/docs', app, document);

  const port = Number(process.env['PORT'] ?? 3000);
  await app.listen(port);
}

bootstrap();
