-- Migration 002: Core schema enums.
-- Enums are defined once and reused across multiple tables to keep
-- the type system coherent. Add new values via ALTER TYPE ... ADD VALUE
-- when the API needs to grow; never rename or remove values that
-- mobile clients may have already cached locally.

-- Certification levels recognized by major agencies.
CREATE TYPE cert_level AS ENUM (
  'OW',         -- Open Water
  'AOW',        -- Advanced Open Water
  'Rescue',     -- Rescue Diver
  'Divemaster', -- Divemaster / equivalent
  'Instructor'  -- Instructor or above
);

-- Certification agencies.
CREATE TYPE cert_agency AS ENUM (
  'PADI',
  'SSI',
  'RAID',
  'CMAS',
  'SDI',
  'other'
);

-- Difficulty rating for a dive site.
CREATE TYPE site_difficulty AS ENUM (
  'beginner',
  'intermediate',
  'advanced',
  'technical'
);

-- Site type taxonomy.
CREATE TYPE site_type AS ENUM (
  'reef',
  'wall',
  'wreck',
  'cave',
  'pinnacle',
  'muck',
  'other'
);

-- How the diver accesses the site.
CREATE TYPE access_type AS ENUM (
  'shore',
  'boat',
  'liveaboard'
);

-- IUCN Red List categories. NE = Not Evaluated, DD = Data Deficient.
CREATE TYPE conservation_status AS ENUM (
  'LC',  -- Least Concern
  'NT',  -- Near Threatened
  'VU',  -- Vulnerable
  'EN',  -- Endangered
  'CR',  -- Critically Endangered
  'DD',  -- Data Deficient
  'NE'   -- Not Evaluated
);

-- How confident the observer is in the species ID.
CREATE TYPE confidence_level AS ENUM (
  'uncertain',
  'likely',
  'certain'
);

-- How strong the current was at the dive site.
CREATE TYPE current_strength AS ENUM (
  'none',
  'light',
  'moderate',
  'strong'
);

-- Gas mixes supported by the logbook.
CREATE TYPE gas_mix AS ENUM (
  'air',
  'nitrox32',
  'nitrox36',
  'trimix'
);

-- Operator types in the platform.
CREATE TYPE operator_type AS ENUM (
  'dive_center',
  'liveaboard',
  'resort'
);

-- Roles within an operator (multi-tenant B2B).
CREATE TYPE operator_role AS ENUM (
  'owner',
  'admin',
  'staff'
);

-- Subscription tiers.
CREATE TYPE subscription_tier AS ENUM (
  'free',
  'starter',
  'pro'
);

-- Subscription status.
CREATE TYPE subscription_status AS ENUM (
  'active',
  'past_due',
  'canceled',
  'trialing'
);

-- Criteria types used to award badges.
CREATE TYPE badge_criteria_type AS ENUM (
  'dive_count',
  'species_count',
  'site_count',
  'region',
  'manual'
);
