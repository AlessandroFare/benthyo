import {
  IsDateString,
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Min,
} from 'class-validator';

export enum GearTypeDto {
  bcd = 'bcd',
  regulator = 'regulator',
  wetsuit = 'wetsuit',
  computer = 'computer',
  fins = 'fins',
  mask = 'mask',
  tank = 'tank',
  other = 'other',
}

export class CreateGearItemDto {
  @IsEnum(GearTypeDto)
  gear_type!: GearTypeDto;

  @IsString()
  @MaxLength(120)
  name!: string;

  @IsOptional()
  @IsString()
  brand?: string;

  @IsOptional()
  @IsString()
  serial_number?: string;

  @IsOptional()
  @IsDateString()
  purchase_date?: string;

  @IsOptional()
  @IsDateString()
  last_service_date?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  service_interval_months?: number;

  @IsOptional()
  @IsString()
  notes?: string;
}

export class UpdateGearItemDto extends CreateGearItemDto {}

export class CreateTripDto {
  @IsString()
  @MaxLength(120)
  name!: string;

  @IsDateString()
  start_date!: string;

  @IsDateString()
  end_date!: string;

  @IsOptional()
  @IsString()
  region?: string;

  @IsOptional()
  @IsUUID()
  operator_id?: string;

  @IsOptional()
  @IsString()
  notes?: string;

  @IsOptional()
  @IsUUID(undefined, { each: true })
  site_ids?: string[];
}
