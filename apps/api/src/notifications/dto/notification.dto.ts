import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEmail, IsObject, IsOptional, IsString } from 'class-validator';

export class SendEmailDto {
  @ApiProperty({ oneOf: [{ type: 'string' }, { type: 'array', items: { type: 'string' } }] })
  @IsEmail({}, { each: true })
  to!: string | string[];

  @ApiProperty()
  @IsString()
  subject!: string;

  @ApiProperty()
  @IsString()
  html!: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  text?: string;
}

export class SendTemplateEmailDto {
  @ApiProperty({ oneOf: [{ type: 'string' }, { type: 'array', items: { type: 'string' } }] })
  @IsEmail({}, { each: true })
  to!: string | string[];

  @ApiProperty({ enum: ['welcome', 'badge_earned', 'operator_invite'] })
  @IsString()
  template!: 'welcome' | 'badge_earned' | 'operator_invite';

  @ApiPropertyOptional()
  @IsOptional()
  @IsObject()
  data?: Record<string, string>;
}