import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsString, IsUUID, MinLength } from 'class-validator';

export class SignWaiverDto {
  @ApiProperty()
  @IsUUID()
  waiver_id!: string;

  @ApiProperty()
  @IsString()
  @MinLength(2)
  signer_name!: string;
}

export class UpsertOperatorWaiverDto {
  @ApiProperty()
  @IsString()
  @MinLength(3)
  title!: string;

  @ApiProperty()
  @IsString()
  @MinLength(20)
  body!: string;
}

export class OperatorSlugParam {
  @ApiProperty()
  @IsString()
  slug!: string;
}
