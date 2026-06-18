import { IsOptional, IsString, IsUUID, MaxLength, MinLength } from 'class-validator';

export class SendMessageDto {
  @IsUUID()
  recipient_id!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(2000)
  body!: string;
}

export class CreateFeedPostDto {
  @IsString()
  @MinLength(1)
  @MaxLength(1000)
  body!: string;

  @IsOptional()
  @IsUUID()
  dive_log_id?: string;

  @IsOptional()
  @IsUUID()
  dive_site_id?: string;

  @IsOptional()
  @IsString()
  photo_url?: string;
}
