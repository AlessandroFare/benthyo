import { ApiProperty } from '@nestjs/swagger';
import { IsString, MaxLength, MinLength } from 'class-validator';

export class ImportUddfDto {
  @ApiProperty({ description: 'Raw UDDF/UDCF XML file contents' })
  @IsString()
  @MinLength(10)
  @MaxLength(5_000_000)
  xml!: string;
}
