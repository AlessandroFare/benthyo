import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsIn,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  IsUrl,
  Max,
  Min,
} from 'class-validator';
import { PaginationDto } from '../../common/dto/pagination.dto';

export class ListSpeciesDto extends PaginationDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  family?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  conservation_status?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  q?: string;
}

export class IdentifySpeciesDto {
  @ApiProperty({ description: 'Public URL of the image to identify' })
  @IsUrl()
  @IsNotEmpty()
  image_url!: string;
}

/**
 * Body for POST /v1/species/:id/embedding. 384-dim float array.
 * Computed on-device via TFLite all-MiniLM-L6-v2.
 */
export class SetEmbeddingDto {
  @ApiProperty({ description: '384-dim float vector', minItems: 384, maxItems: 384 })
  @IsArray()
  @ArrayMaxSize(384)
  @IsNumber({}, { each: true })
  @Min(-1.5, { each: true })
  @Max(1.5, { each: true })
  @Type(() => Number)
  embedding!: number[];

  @ApiPropertyOptional({
    description: 'Where the embedding was generated',
    enum: ['mobile', 'etl', 'manual'],
  })
  @IsOptional()
  @IsIn(['mobile', 'etl', 'manual'])
  source?: 'mobile' | 'etl' | 'manual';

  @ApiPropertyOptional({ description: 'Embedding model version' })
  @IsOptional()
  @IsString()
  model_version?: string;
}

export class SimilarSpeciesQueryDto {
  @ApiProperty({ description: '384-dim float query vector', minItems: 384, maxItems: 384 })
  @IsArray()
  @ArrayMaxSize(384)
  @IsNumber({}, { each: true })
  @Type(() => Number)
  embedding!: number[];

  @ApiPropertyOptional({ description: 'Max results to return (default 5)' })
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(1)
  @Max(50)
  limit?: number;

  @ApiPropertyOptional({ description: 'Minimum cosine similarity 0..1 (default 0.70)' })
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  @Max(1)
  min_similarity?: number;
}
