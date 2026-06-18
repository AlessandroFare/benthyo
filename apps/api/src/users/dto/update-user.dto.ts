import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsEnum, IsOptional, IsString, IsUrl, MaxLength } from 'class-validator';
import { CertAgency, CertLevel } from '../../database/database.types';

export class UpdateUserDto {
  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(100)
  full_name?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsUrl()
  avatar_url?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @MaxLength(500)
  bio?: string;

  @ApiPropertyOptional({ enum: ['OW', 'AOW', 'Rescue', 'Divemaster', 'Instructor'] })
  @IsOptional()
  @IsEnum(['OW', 'AOW', 'Rescue', 'Divemaster', 'Instructor'])
  certification_level?: CertLevel;

  @ApiPropertyOptional({ enum: ['PADI', 'SSI', 'RAID', 'CMAS', 'SDI', 'other'] })
  @IsOptional()
  @IsEnum(['PADI', 'SSI', 'RAID', 'CMAS', 'SDI', 'other'])
  certification_agency?: CertAgency;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  gbif_export_opt_in?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  weekly_digest_opt_in?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  conservation_alerts_opt_in?: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  public_logbook?: boolean;
}
