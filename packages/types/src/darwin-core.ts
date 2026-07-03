import type { DwCBasisOfRecord, DwCOccurrenceStatus } from './enums';

/**
 * Darwin Core Occurrence record (subset used by Benthyo GBIF export).
 * @see https://dwc.tdwg.org/terms/
 */
export interface DarwinCoreOccurrence {
  /** dwc:occurrenceID — globally unique identifier for the occurrence. */
  occurrenceID: string;
  /** dwc:basisOfRecord */
  basisOfRecord: DwCBasisOfRecord;
  /** dwc:occurrenceStatus */
  occurrenceStatus: DwCOccurrenceStatus;
  /** dwc:scientificName */
  scientificName: string;
  /** dwc:taxonID — GBIF or WoRMS taxon key when available. */
  taxonID?: string;
  /** dwc:kingdom */
  kingdom?: string;
  /** dwc:phylum */
  phylum?: string;
  /** dwc:class */
  class?: string;
  /** dwc:order */
  order?: string;
  /** dwc:family */
  family?: string;
  /** dwc:genus */
  genus?: string;
  /** dwc:specificEpithet — parsed from scientific name when possible. */
  specificEpithet?: string;
  /** dwc:decimalLatitude */
  decimalLatitude: number;
  /** dwc:decimalLongitude */
  decimalLongitude: number;
  /** dwc:coordinateUncertaintyInMeters */
  coordinateUncertaintyInMeters?: number;
  /** dwc:geodeticDatum — always WGS84 for GPS observations. */
  geodeticDatum: 'WGS84';
  /** dwc:countryCode — ISO 3166-1 alpha-2. */
  countryCode?: string;
  /** dwc:locality — human-readable place name. */
  locality?: string;
  /** dwc:waterBody */
  waterBody?: string;
  /** dwc:minimumDepthInMeters */
  minimumDepthInMeters?: number;
  /** dwc:maximumDepthInMeters */
  maximumDepthInMeters?: number;
  /** dwc:eventDate — ISO 8601 date or datetime. */
  eventDate: string;
  /** dwc:individualCount */
  individualCount?: number;
  /** dwc:organismQuantity */
  organismQuantity?: number;
  /** dwc:organismQuantityType */
  organismQuantityType?: 'individuals';
  /** dwc:recordedBy — observer username or full name. */
  recordedBy?: string;
  /** dwc:identifiedBy */
  identifiedBy?: string;
  /** dwc:dateIdentified */
  dateIdentified?: string;
  /** dwc:identificationVerificationStatus */
  identificationVerificationStatus?:
    | 'verified by expert'
    | 'verified by community'
    | 'unverified';
  /** dwc:associatedMedia — comma-separated photo URLs. */
  associatedMedia?: string;
  /** dwc:occurrenceRemarks */
  occurrenceRemarks?: string;
  /** dwc:license — SPDX or Creative Commons URI. */
  license?: string;
  /** dwc:rightsHolder */
  rightsHolder?: string;
  /** dwc:institutionCode — always BENTHYO for platform exports. */
  institutionCode: 'BENTHYO';
  /** dwc:collectionCode */
  collectionCode: 'SIGHTINGS';
  /** dwc:catalogNumber — internal sighting UUID. */
  catalogNumber: string;
  /** Benthyo extension: source system provenance. */
  benthyoSource?: string;
  /** Benthyo extension: external occurrence key (GBIF, OBIS). */
  benthyoExternalId?: string;
}

/** Darwin Core Archive metadata file (meta.xml) descriptor. */
export interface DarwinCoreArchiveMetadata {
  core: {
    id: 'occurrence';
    file: string;
    rowType: 'http://rs.tdwg.org/dwc/terms/Occurrence';
    fieldsTerminatedBy: string;
    linesTerminatedBy: string;
    fields: Array<{
      index: number;
      term: string;
    }>;
  };
  /** Optional extension files (e.g. multimedia). */
  extensions?: Array<{
    rowType: string;
    file: string;
    fields: Array<{ index: number; term: string }>;
  }>;
}

/** Export bundle returned by the darwin-core-export Edge Function. */
export interface DarwinCoreExportBundle {
  generated_at: string;
  record_count: number;
  format: 'json' | 'csv' | 'dwca';
  occurrences: DarwinCoreOccurrence[];
  /** Present when format is dwca. */
  archive_url?: string;
}

/** Map an Benthyo sighting row to a Darwin Core occurrence. */
export interface MapToDarwinCoreInput {
  sightingId: string;
  scientificName: string;
  taxonId?: string;
  kingdom?: string;
  phylum?: string;
  class?: string;
  order?: string;
  family?: string;
  genus?: string;
  lat: number;
  lng: number;
  countryCode?: string;
  locality?: string;
  waterBody?: string;
  depthM?: number;
  observedAt: string;
  count: number;
  recordedBy?: string;
  identifiedBy?: string;
  verifiedAt?: string;
  photoUrls?: string[];
  notes?: string;
  license?: string;
  source?: string;
  externalId?: string;
}

/** Default Darwin Core field mapping for CSV/DwC-A export. */
export const DARWIN_CORE_OCCURRENCE_FIELDS: Array<keyof DarwinCoreOccurrence> = [
  'occurrenceID',
  'basisOfRecord',
  'occurrenceStatus',
  'scientificName',
  'taxonID',
  'kingdom',
  'phylum',
  'class',
  'order',
  'family',
  'genus',
  'decimalLatitude',
  'decimalLongitude',
  'geodeticDatum',
  'countryCode',
  'locality',
  'waterBody',
  'minimumDepthInMeters',
  'maximumDepthInMeters',
  'eventDate',
  'individualCount',
  'recordedBy',
  'identifiedBy',
  'dateIdentified',
  'identificationVerificationStatus',
  'associatedMedia',
  'occurrenceRemarks',
  'license',
  'institutionCode',
  'collectionCode',
  'catalogNumber',
];
