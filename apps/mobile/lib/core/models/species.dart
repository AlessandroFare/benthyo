import '../utils/json_utils.dart';
import 'enums.dart';

class Species {
  const Species({
    required this.id,
    required this.scientificName,
    this.commonName,
    this.commonNameIt,
    this.commonNameEs,
    this.family,
    this.genus,
    this.orderName,
    this.className,
    this.phylum,
    this.kingdom,
    this.inatTaxonId,
    this.wormsId,
    this.gbifTaxonKey,
    this.description,
    this.maxDepthM,
    this.minDepthM,
    this.typicalLengthCm,
    this.conservationStatus,
    this.imageUrl,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String scientificName;
  final String? commonName;
  final String? commonNameIt;
  final String? commonNameEs;
  final String? family;
  final String? genus;
  final String? orderName;
  final String? className;
  final String? phylum;
  final String? kingdom;
  final int? inatTaxonId;
  final int? wormsId;
  final int? gbifTaxonKey;
  final String? description;
  final double? maxDepthM;
  final double? minDepthM;
  final double? typicalLengthCm;
  final ConservationStatus? conservationStatus;
  final String? imageUrl;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  String displayName({String locale = 'en'}) {
    if (locale.startsWith('it') && commonNameIt != null) {
      return commonNameIt!;
    }
    if (locale.startsWith('es') && commonNameEs != null) {
      return commonNameEs!;
    }
    return commonName ?? scientificName;
  }

  factory Species.fromJson(Map<String, dynamic> json) => Species(
        id: json['id'] as String,
        scientificName: json['scientific_name'] as String,
        commonName: json['common_name'] as String?,
        commonNameIt: json['common_name_it'] as String?,
        commonNameEs: json['common_name_es'] as String?,
        family: json['family'] as String?,
        genus: json['genus'] as String?,
        orderName: json['order_name'] as String?,
        className: json['class_name'] as String?,
        phylum: json['phylum'] as String?,
        kingdom: json['kingdom'] as String?,
        inatTaxonId: parseInt(json['inat_taxon_id']),
        wormsId: parseInt(json['worms_id']),
        gbifTaxonKey: parseInt(json['gbif_taxon_key']),
        description: json['description'] as String?,
        maxDepthM: parseDouble(json['max_depth_m']),
        minDepthM: parseDouble(json['min_depth_m']),
        typicalLengthCm: parseDouble(json['typical_length_cm']),
        conservationStatus:
            ConservationStatusX.fromDb(json['conservation_status'] as String?),
        imageUrl: json['image_url'] as String?,
        metadata: parseMetadata(json['metadata']),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'scientific_name': scientificName,
        'common_name': commonName,
        'common_name_it': commonNameIt,
        'common_name_es': commonNameEs,
        'family': family,
        'genus': genus,
        'order_name': orderName,
        'class_name': className,
        'phylum': phylum,
        'kingdom': kingdom,
        'inat_taxon_id': inatTaxonId,
        'worms_id': wormsId,
        'gbif_taxon_key': gbifTaxonKey,
        'description': description,
        'max_depth_m': maxDepthM,
        'min_depth_m': minDepthM,
        'typical_length_cm': typicalLengthCm,
        'conservation_status': conservationStatus?.dbValue,
        'image_url': imageUrl,
        'metadata': metadata,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
