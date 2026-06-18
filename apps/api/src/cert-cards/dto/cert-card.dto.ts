import { IsOptional, IsString, IsUUID, MinLength } from 'class-validator';

export class ParseCertCardDto {
  @IsString()
  @MinLength(10)
  raw_text!: string;

  @IsOptional()
  @IsString()
  photo_url?: string;

  @IsOptional()
  @IsUUID()
  operator_id?: string;
}

export class SaveCertCardDto extends ParseCertCardDto {
  @IsOptional()
  @IsString()
  agency?: string;

  @IsOptional()
  @IsString()
  cert_number?: string;

  @IsOptional()
  @IsString()
  cert_level?: string;

  @IsOptional()
  @IsString()
  instructor_name?: string;

  @IsOptional()
  @IsString()
  expiry_date?: string;
}
