enum CertLevel { ow, aow, rescue, divemaster, instructor }

enum CertAgency { padi, ssi, raid, cmas, sdi, other }

enum SiteDifficulty { beginner, intermediate, advanced, technical }

enum SiteType { reef, wall, wreck, cave, pinnacle, muck, other }

enum AccessType { shore, boat, liveaboard }

enum ConservationStatus { lc, nt, vu, en, cr, dd, ne }

enum ConfidenceLevel { uncertain, likely, certain }

enum CurrentStrength { none, light, moderate, strong }

enum GasMix { air, nitrox32, nitrox36, trimix }

enum OperatorType { diveCenter, liveaboard, resort }

enum OperatorRole { owner, admin, staff }

enum SubscriptionTier { free, starter, pro }

enum SubscriptionStatus { active, pastDue, canceled, trialing }

enum BadgeCriteriaType { diveCount, speciesCount, siteCount, region, manual }

enum SightingSource { user, gbif, obis, inaturalist, manual }

extension CertLevelX on CertLevel {
  String get dbValue => switch (this) {
        CertLevel.ow => 'OW',
        CertLevel.aow => 'AOW',
        CertLevel.rescue => 'Rescue',
        CertLevel.divemaster => 'Divemaster',
        CertLevel.instructor => 'Instructor',
      };

  static CertLevel fromDb(String value) => CertLevel.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => CertLevel.ow,
      );
}

extension CertAgencyX on CertAgency {
  String get dbValue => name == 'other' ? 'other' : name.toUpperCase();

  static CertAgency fromDb(String value) {
    if (value == 'other') return CertAgency.other;
    return CertAgency.values.firstWhere(
      (e) => e.dbValue == value,
      orElse: () => CertAgency.padi,
    );
  }
}

extension SiteDifficultyX on SiteDifficulty {
  String get dbValue => name;

  static SiteDifficulty fromDb(String value) =>
      SiteDifficulty.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => SiteDifficulty.beginner,
      );
}

extension SiteTypeX on SiteType {
  String get dbValue => name;

  static SiteType fromDb(String value) => SiteType.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => SiteType.other,
      );
}

extension AccessTypeX on AccessType {
  String get dbValue => name;

  static AccessType fromDb(String value) => AccessType.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => AccessType.shore,
      );
}

extension ConservationStatusX on ConservationStatus {
  String get dbValue => name.toUpperCase();

  static ConservationStatus? fromDb(String? value) {
    if (value == null) return null;
    return ConservationStatus.values.firstWhere(
      (e) => e.dbValue == value,
      orElse: () => ConservationStatus.ne,
    );
  }
}

extension ConfidenceLevelX on ConfidenceLevel {
  String get dbValue => name;

  static ConfidenceLevel fromDb(String value) =>
      ConfidenceLevel.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => ConfidenceLevel.likely,
      );
}

extension CurrentStrengthX on CurrentStrength {
  String get dbValue => name;

  static CurrentStrength? fromDb(String? value) {
    if (value == null) return null;
    return CurrentStrength.values.firstWhere(
      (e) => e.dbValue == value,
      orElse: () => CurrentStrength.none,
    );
  }
}

extension GasMixX on GasMix {
  String get dbValue => switch (this) {
        GasMix.air => 'air',
        GasMix.nitrox32 => 'nitrox32',
        GasMix.nitrox36 => 'nitrox36',
        GasMix.trimix => 'trimix',
      };

  static GasMix fromDb(String value) => GasMix.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => GasMix.air,
      );
}

extension OperatorTypeX on OperatorType {
  String get dbValue => switch (this) {
        OperatorType.diveCenter => 'dive_center',
        OperatorType.liveaboard => 'liveaboard',
        OperatorType.resort => 'resort',
      };

  static OperatorType fromDb(String value) => OperatorType.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => OperatorType.diveCenter,
      );
}

extension SubscriptionTierX on SubscriptionTier {
  String get dbValue => name;

  static SubscriptionTier fromDb(String value) =>
      SubscriptionTier.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => SubscriptionTier.free,
      );
}

extension SubscriptionStatusX on SubscriptionStatus {
  String get dbValue => switch (this) {
        SubscriptionStatus.pastDue => 'past_due',
        _ => name,
      };

  static SubscriptionStatus fromDb(String value) =>
      SubscriptionStatus.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => SubscriptionStatus.trialing,
      );
}

extension BadgeCriteriaTypeX on BadgeCriteriaType {
  String get dbValue => switch (this) {
        BadgeCriteriaType.diveCount => 'dive_count',
        BadgeCriteriaType.speciesCount => 'species_count',
        BadgeCriteriaType.siteCount => 'site_count',
        BadgeCriteriaType.region => 'region',
        BadgeCriteriaType.manual => 'manual',
      };

  static BadgeCriteriaType fromDb(String value) =>
      BadgeCriteriaType.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => BadgeCriteriaType.manual,
      );
}

extension SightingSourceX on SightingSource {
  String get dbValue => name;

  static SightingSource fromDb(String value) =>
      SightingSource.values.firstWhere(
        (e) => e.dbValue == value,
        orElse: () => SightingSource.user,
      );
}
