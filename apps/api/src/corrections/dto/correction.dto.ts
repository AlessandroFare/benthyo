import { IsString, IsUUID, MaxLength, MinLength } from 'class-validator';

export class SuggestCorrectionDto {
  @IsUUID()
  sighting_id!: string;

  @IsUUID()
  proposed_species_id!: string;

  @IsString()
  @MinLength(5)
  @MaxLength(500)
  reason!: string;
}
