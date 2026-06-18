import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsEnum,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Matches,
  Max,
  Min,
} from 'class-validator';
import {
  AccessType,
  SiteDifficulty,
  SiteType,
} from '../../database/database.types';
import { PaginationDto } from '../../common/dto/pagination.dto';

export class ListDiveSitesDto extends PaginationDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @Length(2, 2)
  country_code?: string;

  @ApiPropertyOptional({ enum: ['beginner', 'intermediate', 'advanced', 'technical'] })
  @IsOptional()
  @IsEnum(['beginner', 'intermediate', 'advanced', 'technical'])
  difficulty?: SiteDifficulty;

  @ApiPropertyOptional({ enum: ['reef', 'wall', 'wreck', 'cave', 'pinnacle', 'muck', 'other'] })
  @IsOptional()
  @IsEnum(['reef', 'wall', 'wreck', 'cave', 'pinnacle', 'muck', 'other'])
  site_type?: SiteType;

  @ApiPropertyOptional({ enum: ['shore', 'boat', 'liveaboard'] })
  @IsOptional()
  @IsEnum(['shore', 'boat', 'liveaboard'])
  access_type?: AccessType;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  @Type(() => Boolean)
  verified?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  region?: string;
}

export class NearbyDiveSitesDto {
  @ApiProperty()
  @Type(() => Number)
  @IsNumber()
  @Min(-90)
  @Max(90)
  lat!: number;

  @ApiProperty()
  @Type(() => Number)
  @IsNumber()
  @Min(-180)
  @Max(180)
  lng!: number;

  @ApiPropertyOptional({ default: 50 })
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0.1)
  @Max(500)
  radius_km = 50;
}

export class SearchDiveSitesDto extends PaginationDto {
  @ApiProperty()
  @IsString()
  q!: string;
}

export class CreateDiveSiteDto {
  @ApiProperty()
  @IsString()
  name!: string;

  @ApiProperty()
  @IsString()
  @Matches(/^[a-z0-9-]+$/)
  slug!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  description?: string;

  @ApiProperty()
  @Type(() => Number)
  @IsNumber()
  @Min(-90)
  @Max(90)
  lat!: number;

  @ApiProperty()
  @Type(() => Number)
  @IsNumber()
  @Min(-180)
  @Max(180)
  lng!: number;

  @ApiProperty()
  @IsString()
  @Length(2, 2)
  country_code!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  region?: string;

  @ApiProperty()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  depth_min!: number;

  @ApiProperty()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  depth_max!: number;

  @ApiProperty({ enum: ['beginner', 'intermediate', 'advanced', 'technical'] })
  @IsEnum(['beginner', 'intermediate', 'advanced', 'technical'])
  difficulty!: SiteDifficulty;

  @ApiProperty({ enum: ['reef', 'wall', 'wreck', 'cave', 'pinnacle', 'muck', 'other'] })
  @IsEnum(['reef', 'wall', 'wreck', 'cave', 'pinnacle', 'muck', 'other'])
  site_type!: SiteType;

  @ApiProperty({ enum: ['shore', 'boat', 'liveaboard'] })
  @IsEnum(['shore', 'boat', 'liveaboard'])
  access_type!: AccessType;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  metadata?: Record<string, unknown>;
}

export class UpdateDiveSiteDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  name?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  description?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(-90)
  @Max(90)
  lat?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(-180)
  @Max(180)
  lng?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @Length(2, 2)
  country_code?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  region?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  depth_min?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  depth_max?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEnum(['beginner', 'intermediate', 'advanced', 'technical'])
  difficulty?: SiteDifficulty;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEnum(['reef', 'wall', 'wreck', 'cave', 'pinnacle', 'muck', 'other'])
  site_type?: SiteType;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEnum(['shore', 'boat', 'liveaboard'])
  access_type?: AccessType;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  metadata?: Record<string, unknown>;
}

export class ListSiteSightingsDto extends PaginationDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  species_id?: string;
}
