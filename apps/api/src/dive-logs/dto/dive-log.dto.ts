import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsArray,
  IsDateString,
  IsEnum,
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';
import { PaginationDto } from '../../common/dto/pagination.dto';

export class CreateDiveLogDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  dive_site_id?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUUID()
  operator_id?: string;

  @ApiProperty()
  @IsDateString()
  dive_date!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsInt()
  dive_number?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  entry_time?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsDateString()
  exit_time?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  max_depth_m?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  avg_depth_m?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsInt()
  duration_min?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  water_temp_surface_c?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  water_temp_bottom_c?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  visibility_m?: number;

  @ApiPropertyOptional({ enum: ['none', 'light', 'moderate', 'strong'] })
  @IsOptional()
  @IsEnum(['none', 'light', 'moderate', 'strong'])
  current_strength?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  tank_start_bar?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  tank_end_bar?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  tank_size_l?: number;

  @ApiPropertyOptional({ enum: ['air', 'nitrox32', 'nitrox36', 'trimix'] })
  @IsOptional()
  @IsEnum(['air', 'nitrox32', 'nitrox36', 'trimix'])
  gas_mix?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  buddy_name?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  notes?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(5)
  rating?: number;

  @ApiPropertyOptional({
    description: 'Depth/time samples [{t_sec, depth_m}] from dive computer',
  })
  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => ProfileSampleDto)
  profile_samples?: ProfileSampleDto[];
}

export class ProfileSampleDto {
  @IsNumber()
  t_sec!: number;

  @IsNumber()
  depth_m!: number;
}

export class UpdateDiveLogDto extends CreateDiveLogDto {}

export class ListDiveLogsDto extends PaginationDto {}

export class SyncDiveLogsDto {
  @ApiProperty({ type: [CreateDiveLogDto] })
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CreateDiveLogDto)
  logs!: CreateDiveLogDto[];
}
