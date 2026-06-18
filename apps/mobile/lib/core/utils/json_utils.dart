Map<String, dynamic> parseMetadata(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return {};
}

List<String> parseStringList(dynamic raw) {
  if (raw is List) {
    return raw.map((e) => e.toString()).toList();
  }
  return [];
}

List<int> parseIntList(dynamic raw) {
  if (raw is List) {
    return raw.map((e) => (e as num).toInt()).toList();
  }
  return [];
}

List<String> parseUuidList(dynamic raw) {
  if (raw is List) {
    return raw.map((e) => e.toString()).toList();
  }
  return [];
}

double? parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int? parseInt(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}
