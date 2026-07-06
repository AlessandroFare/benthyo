import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';
import { APP_FILTER, APP_INTERCEPTOR } from '@nestjs/core';
import { join } from 'path';
import supabaseConfig from './config/supabase.config';
import r2Config from './config/r2.config';
import resendConfig from './config/resend.config';
import aiVisionConfig from './config/ai-vision.config';
import { DatabaseModule } from './database/database.module';
import { StorageModule } from './storage/storage.module';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { DiveSitesModule } from './dive-sites/dive-sites.module';
import { SpeciesModule } from './species/species.module';
import { SightingsModule } from './sightings/sightings.module';
import { DiveLogsModule } from './dive-logs/dive-logs.module';
import { OperatorsModule } from './operators/operators.module';
import { MediaModule } from './media/media.module';
import { SearchModule } from './search/search.module';
import { NotificationsModule } from './notifications/notifications.module';
import { HealthModule } from './health/health.module';
import { WaiversModule } from './waivers/waivers.module';
import { PublicDataModule } from './public-data/public-data.module';
import { CorrectionsModule } from './corrections/corrections.module';
import { GearModule } from './gear/gear.module';
import { TripsModule } from './trips/trips.module';
import { MedicalModule } from './medical/medical.module';
import { ReviewsModule } from './reviews/reviews.module';
import { ApiKeysModule } from './api-keys/api-keys.module';
import { PaymentsModule } from './payments/payments.module';
import { CertCardsModule } from './cert-cards/cert-cards.module';
import { RentalGearModule } from './rental-gear/rental-gear.module';
import { SyncExtensionsModule } from './sync-extensions/sync-extensions.module';
import { SocialModule } from './social/social.module';
import { MarketplaceModule } from './marketplace/marketplace.module';
import { BleSyncModule } from './ble-sync/ble-sync.module';
import { AdminModule } from './admin/admin.module';
import { BookingsModule } from './bookings/bookings.module';
import { LoggingInterceptor } from './common/interceptors/logging.interceptor';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      envFilePath: [
        join(process.cwd(), '.env'),
        join(process.cwd(), '..', '.env'),
        join(__dirname, '..', '..', '.env'),
      ],
      load: [supabaseConfig, r2Config, resendConfig, aiVisionConfig],
    }),
    ThrottlerModule.forRoot([
      {
        ttl: 60_000,
        limit: 120,
      },
    ]),
    DatabaseModule,
    StorageModule,
    AuthModule,
    UsersModule,
    DiveSitesModule,
    SpeciesModule,
    SightingsModule,
    DiveLogsModule,
    OperatorsModule,
    MediaModule,
    SearchModule,
    NotificationsModule,
    HealthModule,
    WaiversModule,
    PublicDataModule,
    CorrectionsModule,
    GearModule,
    TripsModule,
    MedicalModule,
    ReviewsModule,
    ApiKeysModule,
    PaymentsModule,
    CertCardsModule,
    RentalGearModule,
    SyncExtensionsModule,
    SocialModule,
    MarketplaceModule,
    BleSyncModule,
    AdminModule,
    BookingsModule,
  ],
  providers: [
    {
      provide: APP_INTERCEPTOR,
      useClass: LoggingInterceptor,
    },
    {
      provide: APP_FILTER,
      useClass: HttpExceptionFilter,
    },
  ],
})
export class AppModule {}
