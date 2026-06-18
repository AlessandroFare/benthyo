import { IsBoolean, IsEnum, IsInt, IsOptional, IsString, MaxLength, Min, MinLength } from 'class-validator';

export enum MarketplaceListingTypeDto {
  course = 'course',
  fun_dive = 'fun_dive',
  liveaboard = 'liveaboard',
  gear_rental = 'gear_rental',
  certification = 'certification',
}

export class CreateMarketplaceListingDto {
  @IsEnum(MarketplaceListingTypeDto)
  listing_type!: MarketplaceListingTypeDto;

  @IsString()
  @MinLength(3)
  @MaxLength(120)
  title!: string;

  @IsString()
  @MinLength(10)
  @MaxLength(2000)
  description!: string;

  @IsInt()
  @Min(0)
  price_cents!: number;

  @IsOptional()
  @IsString()
  @MaxLength(3)
  currency?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  region?: string;
}

export class UpdateMarketplaceListingDto {
  @IsOptional()
  @IsEnum(MarketplaceListingTypeDto)
  listing_type?: MarketplaceListingTypeDto;

  @IsOptional()
  @IsString()
  @MinLength(3)
  @MaxLength(120)
  title?: string;

  @IsOptional()
  @IsString()
  @MinLength(10)
  @MaxLength(2000)
  description?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  price_cents?: number;

  @IsOptional()
  @IsString()
  region?: string;

  @IsOptional()
  @IsBoolean()
  is_active?: boolean;
}
