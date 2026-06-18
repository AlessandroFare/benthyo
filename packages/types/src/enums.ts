/** Certification levels recognized by major agencies. */
export type CertLevel = 'OW' | 'AOW' | 'Rescue' | 'Divemaster' | 'Instructor';

/** Certification agencies. */
export type CertAgency = 'PADI' | 'SSI' | 'RAID' | 'CMAS' | 'SDI' | 'other';

/** Difficulty rating for a dive site. */
export type SiteDifficulty = 'beginner' | 'intermediate' | 'advanced' | 'technical';

/** Site type taxonomy. */
export type SiteType = 'reef' | 'wall' | 'wreck' | 'cave' | 'pinnacle' | 'muck' | 'other';

/** How the diver accesses the site. */
export type AccessType = 'shore' | 'boat' | 'liveaboard';

/** IUCN Red List categories. */
export type ConservationStatus = 'LC' | 'NT' | 'VU' | 'EN' | 'CR' | 'DD' | 'NE';

/** How confident the observer is in the species ID. */
export type ConfidenceLevel = 'uncertain' | 'likely' | 'certain';

/** How strong the current was at the dive site. */
export type CurrentStrength = 'none' | 'light' | 'moderate' | 'strong';

/** Gas mixes supported by the logbook. */
export type GasMix = 'air' | 'nitrox32' | 'nitrox36' | 'trimix';

/** Operator types in the platform. */
export type OperatorType = 'dive_center' | 'liveaboard' | 'resort';

/** Roles within an operator (multi-tenant B2B). */
export type OperatorRole = 'owner' | 'admin' | 'staff';

/** Subscription tiers. */
export type SubscriptionTier = 'free' | 'starter' | 'pro';

/** Subscription status. */
export type SubscriptionStatus = 'active' | 'past_due' | 'canceled' | 'trialing';

/** Criteria types used to award badges. */
export type BadgeCriteriaType =
  | 'dive_count'
  | 'species_count'
  | 'site_count'
  | 'region'
  | 'manual';

/** Provenance of a sighting record. */
export type SightingSource = 'user' | 'gbif' | 'obis' | 'inaturalist' | 'manual';

/** Darwin Core basis of record. */
export type DwCBasisOfRecord =
  | 'HumanObservation'
  | 'MachineObservation'
  | 'PreservedSpecimen'
  | 'MaterialSample';

/** Darwin Core occurrence status. */
export type DwCOccurrenceStatus = 'present' | 'absent';
