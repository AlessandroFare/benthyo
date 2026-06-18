import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/species.dart';
import '../../core/supabase/supabase_client.dart';

/// Scores species matches for identification search.
int scoreSpeciesMatch(Species species, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return 0;

  var score = 0;
  if (species.scientificName.toLowerCase() == q) score += 100;
  if (species.scientificName.toLowerCase().startsWith(q)) score += 50;
  if (species.scientificName.toLowerCase().contains(q)) score += 20;

  for (final name in [
    species.commonName,
    species.commonNameIt,
    species.commonNameEs,
  ]) {
    if (name == null) continue;
    final lower = name.toLowerCase();
    if (lower == q) {
      score += 80;
    } else if (lower.startsWith(q)) {
      score += 40;
    } else if (lower.contains(q)) {
      score += 15;
    }
  }

  if (species.family?.toLowerCase().contains(q) ?? false) score += 10;
  if (species.genus?.toLowerCase().startsWith(q) ?? false) score += 25;

  return score;
}

List<Species> rankSpeciesMatches(List<Species> species, String query) {
  final scored = species
      .map((s) => MapEntry(s, scoreSpeciesMatch(s, query)))
      .where((e) => e.value > 0)
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return scored.map((e) => e.key).toList();
}

class SpeciesRepository {
  SpeciesRepository(this._client);

  final SupabaseClient _client;

  Future<List<Species>> fetchAll({int limit = 100, int offset = 0}) async {
    final data = await _client
        .from('species')
        .select()
        .order('scientific_name')
        .range(offset, offset + limit - 1);
    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(Species.fromJson).toList();
  }

  Future<Species?> fetchById(String id) async {
    final data =
        await _client.from('species').select().eq('id', id).maybeSingle();
    if (data == null) return null;
    return Species.fromJson(data);
  }

  Future<List<Species>> search(String query) async {
    if (query.trim().isEmpty) return fetchAll();
    final data = await _client
        .from('species')
        .select()
        .or(
          'scientific_name.ilike.%$query%,common_name.ilike.%$query%,common_name_it.ilike.%$query%,family.ilike.%$query%',
        )
        .limit(50);
    final rows = (data as List).cast<Map<String, dynamic>>();
    final results = rows.map(Species.fromJson).toList();
    return rankSpeciesMatches(results, query);
  }
}

final speciesRepositoryProvider = Provider<SpeciesRepository>((ref) {
  return SpeciesRepository(ref.watch(supabaseClientProvider));
});

final speciesListProvider = FutureProvider<List<Species>>((ref) {
  return ref.watch(speciesRepositoryProvider).fetchAll();
});

final speciesProvider = FutureProvider.family<Species?, String>((ref, id) {
  return ref.watch(speciesRepositoryProvider).fetchById(id);
});

final speciesSearchProvider =
    FutureProvider.family<List<Species>, String>((ref, query) {
  return ref.watch(speciesRepositoryProvider).search(query);
});
