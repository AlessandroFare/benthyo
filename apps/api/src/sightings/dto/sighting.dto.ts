import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import {
  IsArray,
  IsEnum,
  IsISO8601,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Min,
} from 'class-validator';
import { PaginationDto } from '../../common/dto/pagination.dto';

export class ListSightingsDto extends PaginationDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  dive_site_id?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  species_id?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  user_id?: string;
}

export class CreateSightingDto {
  @ApiProperty()
  @IsUUID()
  dive_site_id!: string;

  @ApiProperty()
  @IsUUID()
  species_id!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  dive_log_id?: string;

  @ApiProperty()
  @IsISO8601()
  observed_at!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @Min(0)
  depth_m?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  water_temp_c?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  visibility_m?: number;

  @ApiPropertyOptional({ default: 1 })
  @IsOptional()
  @IsNumber()
  @Min(1)
  count?: number;

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  behavior_tags?: string[];

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  photo_urls?: string[];

  @ApiPropertyOptional({ enum: ['uncertain', 'likely', 'certain'] })
  @IsOptional()
  @IsEnum(['uncertain', 'likely', 'certain'])
  confidence_level?: 'uncertain' | 'likely' | 'certain';

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  lat?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  lng?: number;
}

export class UpdateSightingDto extends PartialType(CreateSightingDto) {}
