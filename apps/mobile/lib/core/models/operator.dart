import 'package:latlong2/latlong.dart';

import '../utils/geo_utils.dart';
import '../utils/json_utils.dart';
import 'enums.dart';

class Operator {
  const Operator({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.website,
    this.email,
    this.phone,
    this.address,
    this.location,
    this.countryCode,
    required this.operatorType,
    this.padiStoreId,
    this.ssiCenterId,
    required this.subscriptionTier,
    required this.subscriptionStatus,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? website;
  final String? email;
  final String? phone;
  final String? address;
  final LatLng? location;
  final String? countryCode;
  final OperatorType operatorType;
  final String? padiStoreId;
  final String? ssiCenterId;
  final SubscriptionTier subscriptionTier;
  final SubscriptionStatus subscriptionStatus;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Operator.fromJson(Map<String, dynamic> json) => Operator(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        description: json['description'] as String?,
        website: json['website'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        address: json['address'] as String?,
        location: parseGeography(json['location']),
        countryCode: json['country_code'] as String?,
        operatorType: OperatorTypeX.fromDb(json['operator_type'] as String),
        padiStoreId: json['padi_store_id'] as String?,
        ssiCenterId: json['ssi_center_id'] as String?,
        subscriptionTier:
            SubscriptionTierX.fromDb(json['subscription_tier'] as String),
        subscriptionStatus:
            SubscriptionStatusX.fromDb(json['subscription_status'] as String),
        metadata: parseMetadata(json['metadata']),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'description': description,
        'website': website,
        'email': email,
        'phone': phone,
        'address': address,
        'location': location != null ? geographyToWkt(location!) : null,
        'country_code': countryCode,
        'operator_type': operatorType.dbValue,
        'padi_store_id': padiStoreId,
        'ssi_center_id': ssiCenterId,
        'subscription_tier': subscriptionTier.dbValue,
        'subscription_status': subscriptionStatus.dbValue,
        'metadata': metadata,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
