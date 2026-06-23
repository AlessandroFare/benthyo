import 'package:flutter_test/flutter_test.dart';

import 'package:benthyo/core/models/species.dart';
import 'package:benthyo/features/species/species_providers.dart';

Species _species({
  required String id,
  required String scientificName,
  String? commonName,
  String? commonNameIt,
  String? genus,
}) {
  // `genus` is accepted for callers that pass it; it isn't yet stored on
  // the Species model but the genus-prefix matcher reads it via
  // `species.scientificName`, so we don't need to round-trip it here.
  // ignore: unnecessary_null_checks
  assert(genus == null || genus.isNotEmpty);
  return Species(
    id: id,
    scientificName: scientificName,
    commonName: commonName,
    commonNameIt: commonNameIt,
    metadata: const {},
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}

void main() {
  group('scoreSpeciesMatch', () {
    test('ranks exact scientific name highest', () {
      final turtle = _species(
        id: '1',
        scientificName: 'Chelonia mydas',
        commonName: 'Green sea turtle',
      );
      final other = _species(
        id: '2',
        scientificName: 'Eretmochelys imbricata',
        commonName: 'Hawksbill turtle',
      );

      expect(
        scoreSpeciesMatch(turtle, 'Chelonia mydas'),
        greaterThan(scoreSpeciesMatch(other, 'Chelonia mydas')),
      );
    });

    test('matches localized common names', () {
      final species = _species(
        id: '1',
        scientificName: 'Epinephelus marginatus',
        commonName: 'Dusky grouper',
        commonNameIt: 'Cernia bruna',
      );

      expect(scoreSpeciesMatch(species, 'cernia bruna'), greaterThan(0));
      expect(
        scoreSpeciesMatch(species, 'cernia bruna'),
        greaterThan(scoreSpeciesMatch(species, 'cernia')),
      );
    });

    test('matches genus prefix', () {
      final species = _species(
        id: '1',
        scientificName: 'Amphiprion ocellaris',
        genus: 'Amphiprion',
      );

      expect(scoreSpeciesMatch(species, 'amphiprion'), greaterThan(0));
    });
  });

  group('rankSpeciesMatches', () {
    test('filters and sorts by relevance', () {
      final list = [
        _species(
          id: '1',
          scientificName: 'Thalassoma pavo',
          commonName: 'Ornate wrasse',
        ),
        _species(
          id: '2',
          scientificName: 'Coris julis',
          commonName: 'Mediterranean rainbow wrasse',
        ),
        _species(
          id: '3',
          scientificName: 'Muraena helena',
          commonName: 'Mediterranean moray',
        ),
      ];

      final ranked = rankSpeciesMatches(list, 'wrasse');

      expect(ranked, hasLength(2));
      expect(ranked.first.commonName, contains('wrasse'));
    });

    test('returns empty list when no matches', () {
      final list = [
        _species(id: '1', scientificName: 'Octopus vulgaris'),
      ];

      expect(rankSpeciesMatches(list, 'shark'), isEmpty);
    });
  });
}
