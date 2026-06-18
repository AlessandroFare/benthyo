import {
  IsInt,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  Min,
} from 'class-validator';

export class CreateSiteReviewDto {
  @IsUUID()
  dive_site_id!: string;

  @IsInt()
  @Min(1)
  @Max(5)
  rating!: number;

  @IsOptional()
  @IsString()
  body?: string;

  @IsOptional()
  @IsNumber()
  visibility_m?: number;

  @IsOptional()
  @IsString()
  current_note?: string;

  @IsOptional()
  @IsUUID()
  dive_log_id?: string;
}
