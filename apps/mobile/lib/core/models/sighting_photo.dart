class SightingPhoto {
  const SightingPhoto({
    required this.id,
    required this.sightingId,
    required this.userId,
    required this.storagePath,
    required this.publicUrl,
    this.caption,
    this.sortOrder = 0,
    required this.createdAt,
  });

  final String id;
  final String sightingId;
  final String userId;
  final String storagePath;
  final String publicUrl;
  final String? caption;
  final int sortOrder;
  final DateTime createdAt;

  factory SightingPhoto.fromJson(Map<String, dynamic> json) => SightingPhoto(
        id: json['id'] as String,
        sightingId: json['sighting_id'] as String,
        userId: json['user_id'] as String,
        storagePath: json['storage_path'] as String,
        publicUrl: json['public_url'] as String,
        caption: json['caption'] as String?,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sighting_id': sightingId,
        'user_id': userId,
        'storage_path': storagePath,
        'public_url': publicUrl,
        'caption': caption,
        'sort_order': sortOrder,
        'created_at': createdAt.toIso8601String(),
      };
}
