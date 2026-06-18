import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString } from 'class-validator';
import { PaginationDto } from '../../common/dto/pagination.dto';

export class UnifiedSearchDto extends PaginationDto {
  @ApiProperty()
  @IsString()
  q!: string;

  @ApiPropertyOptional({ enum: ['all', 'dive_sites', 'species'] })
  @IsOptional()
  @IsIn(['all', 'dive_sites', 'species'])
  type?: 'all' | 'dive_sites' | 'species';
}

export interface SearchHit {
  type: 'dive_site' | 'species';
  id: string;
  title: string;
  subtitle: string | null;
  slug?: string;
  image_url?: string | null;
}
