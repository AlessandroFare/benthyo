import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsEmail,
  IsEnum,
  IsInt,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  Matches,
  Max,
  Min,
} from 'class-validator';
import { OperatorRole, OperatorType } from '../../database/database.types';
import { PaginationDto } from '../../common/dto/pagination.dto';

export class ListOperatorsDto extends PaginationDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  country_code?: string;

  @ApiPropertyOptional({ enum: ['dive_center', 'liveaboard', 'resort'] })
  @IsOptional()
  @IsEnum(['dive_center', 'liveaboard', 'resort'])
  operator_type?: OperatorType;
}

export class CreateOperatorDto {
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

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  website?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEmail()
  email?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  phone?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  address?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  lat?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  lng?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  country_code?: string;

  @ApiProperty({ enum: ['dive_center', 'liveaboard', 'resort'] })
  @IsEnum(['dive_center', 'liveaboard', 'resort'])
  operator_type!: OperatorType;
}

export class UpdateOperatorDto {
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
  @IsString()
  website?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEmail()
  email?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  phone?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  address?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  metadata?: Record<string, unknown>;
}

export class InviteOperatorUserDto {
  @ApiProperty()
  @IsUUID()
  user_id!: string;

  @ApiProperty({ enum: ['owner', 'admin', 'staff'] })
  @IsEnum(['owner', 'admin', 'staff'])
  role!: OperatorRole;
}

export class LinkDiveSiteDto {
  @ApiProperty()
  @IsUUID()
  dive_site_id!: string;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  is_primary = false;
}

export class ListOperatorCustomersDto extends PaginationDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  q?: string;
}

export class ListOperatorSpeciesDto extends PaginationDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  q?: string;
}

export class OperatorAnalyticsQueryDto {
  @ApiPropertyOptional({ default: 30 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(365)
  window_days = 30;
}

export class OperatorRosterQueryDto {
  @ApiPropertyOptional({
    description: 'Roster date (YYYY-MM-DD). Defaults to today.',
    example: '2026-06-18',
  })
  @IsOptional()
  @Matches(/^\d{4}-\d{2}-\d{2}$/, { message: 'date must be in YYYY-MM-DD format' })
  date?: string;
}
