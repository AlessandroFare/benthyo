import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString } from 'class-validator';

export class PresignedUploadDto {
  @ApiProperty({ example: 'sightings' })
  @IsString()
  @IsIn(['sightings', 'avatars', 'dive-sites', 'species'])
  folder!: string;

  @ApiProperty({ example: 'photo.jpg' })
  @IsString()
  file_name!: string;

  @ApiProperty({ example: 'image/jpeg' })
  @IsString()
  content_type!: string;

  @ApiPropertyOptional({ default: 300 })
  @IsOptional()
  expires_in?: number;
}
