import { IsIn, IsOptional, IsString, IsUUID } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

/**
 * Body for POST /v1/soft-delete. Pass a table name (one of the six
 * core entities) and the row id. The RPC enforces authorisation.
 */
export class SoftDeleteDto {
  @ApiProperty({
    description: 'Table to soft-delete from. One of the audited core tables.',
    enum: ['users', 'dive_sites', 'species', 'sightings', 'dive_logs', 'operators'],
  })
  @IsIn(['users', 'dive_sites', 'species', 'sightings', 'dive_logs', 'operators'])
  table!: 'users' | 'dive_sites' | 'species' | 'sightings' | 'dive_logs' | 'operators';

  @ApiProperty({ description: 'UUID of the row to soft-delete' })
  @IsUUID()
  id!: string;

  @ApiPropertyOptional({ description: 'Reason (audited for GDPR Article 17)' })
  @IsOptional()
  @IsString()
  reason?: string;
}

export class RestoreSoftDeletedDto {
  @ApiProperty({
    description: 'Table to restore into',
    enum: ['users', 'dive_sites', 'species', 'sightings', 'dive_logs', 'operators'],
  })
  @IsIn(['users', 'dive_sites', 'species', 'sightings', 'dive_logs', 'operators'])
  table!: 'users' | 'dive_sites' | 'species' | 'sightings' | 'dive_logs' | 'operators';

  @ApiProperty({ description: 'UUID of the row to restore' })
  @IsUUID()
  id!: string;
}
