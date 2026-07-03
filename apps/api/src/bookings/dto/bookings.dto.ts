import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsBoolean,
  IsDateString,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
import { Type } from 'class-transformer';

export class CreateBookingSlotDto {
  @ApiProperty()
  @IsUUID()
  dive_site_id!: string;

  @ApiProperty({ example: '2026-07-15' })
  @IsDateString()
  trip_date!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  depart_at?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  boat_id?: string;

  @ApiProperty({ example: 5000 })
  @IsInt()
  @Min(0)
  price_cents!: number;

  @ApiPropertyOptional({ default: 'eur' })
  @IsOptional()
  @IsString()
  @MinLength(3)
  @MaxLength(3)
  currency?: string;

  @ApiProperty({ example: 8 })
  @IsInt()
  @Min(1)
  @Max(100)
  max_capacity!: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;
}

export class UpdateBookingSlotDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  trip_date?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  depart_at?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsInt()
  @Min(0)
  price_cents?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  max_capacity?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  is_active?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;
}

export class CreateBookingDto {
  @ApiProperty()
  @IsUUID()
  slot_id!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(120)
  diver_name?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  diver_email?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  diver_phone?: string;
}

export class SlotQueryDto {
  @ApiPropertyOptional({ example: '2026-07-01' })
  @IsOptional()
  @IsDateString()
  from_date?: string;

  @ApiPropertyOptional({ example: '2026-07-31' })
  @IsOptional()
  @IsDateString()
  to_date?: string;

  @ApiPropertyOptional({ example: 45.0 })
  @IsOptional()
  @Type(() => Number)
  lat?: number;

  @ApiPropertyOptional({ example: 12.0 })
  @IsOptional()
  @Type(() => Number)
  lng?: number;

  @ApiPropertyOptional({ example: 100 })
  @IsOptional()
  @Type(() => Number)
  radius_km?: number;
}
