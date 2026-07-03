import {
  ArrayMaxSize,
  IsArray,
  IsNumber,
  IsOptional,
  IsString,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';

export class BleDiveSampleDto {
  @IsNumber()
  @Min(0)
  t_sec!: number;

  @IsNumber()
  @Min(0)
  depth_m!: number;
}

export class BleDivePayloadDto {
  @IsString()
  dive_date!: string;

  @IsNumber()
  @Min(0)
  max_depth_m!: number;

  @IsNumber()
  @Min(1)
  duration_min!: number;

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => BleDiveSampleDto)
  profile_samples?: BleDiveSampleDto[];
}

export class RegisterBleDeviceDto {
  @IsString()
  @MaxLength(120)
  device_name!: string;

  @IsString()
  @MaxLength(120)
  device_uuid!: string;

  @IsOptional()
  @IsString()
  manufacturer?: string;

  @IsOptional()
  @IsString()
  model?: string;
}

export class BleImportDto {
  @IsString()
  device_uuid!: string;

  @IsArray()
  @ArrayMaxSize(200, {
    message: 'BLE import accepts at most 200 dives per call',
  })
  @ValidateNested({ each: true })
  @Type(() => BleDivePayloadDto)
  dives!: BleDivePayloadDto[];
}
