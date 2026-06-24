import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';

final quizSpeciesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final data = await ref.watch(supabaseClientProvider).from('user_life_list').select(
        'species_id, species:species(id, scientific_name, common_name, image_url)',
      ).eq('user_id', user.id).limit(30);
  return (data as List).cast<Map<String, dynamic>>();
});

class SpeciesQuizScreen extends ConsumerStatefulWidget {
  const SpeciesQuizScreen({super.key});

  @override
  ConsumerState<SpeciesQuizScreen> createState() => _SpeciesQuizScreenState();
}

class _SpeciesQuizScreenState extends ConsumerState<SpeciesQuizScreen> {
  final _rng = Random();
  int _score = 0;
  int _round = 0;
  Map<String, dynamic>? _question;
  List<Map<String, dynamic>> _choices = [];
  String? _feedback;

  void _nextQuestion(List<Map<String, dynamic>> pool) {
    if (pool.length < 4) return;
    final correct = pool[_rng.nextInt(pool.length)];
    final species = correct['species'] as Map<String, dynamic>?;
    if (species == null) return;

    final others = pool.where((e) => e['species_id'] != correct['species_id']).toList()
      ..shuffle(_rng);
    _choices = [species, ...others.take(3).map((e) => e['species'] as Map<String, dynamic>)]
      ..shuffle(_rng);

    setState(() {
      _question = species;
      _feedback = null;
      _round += 1;
    });
  }

  void _answer(Map<String, dynamic> choice) {
    final correct = _question!['id'] == choice['id'];
    setState(() {
      _feedback = correct ? 'Correct!' : 'It was ${_question!['common_name'] ?? _question!['scientific_name']}';
      if (correct) _score += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final speciesAsync = ref.watch(quizSpeciesProvider);

    return AppScaffold(
      title: 'Species quiz',
      body: AsyncValueWidget(
        value: speciesAsync,
        isEmpty: (items) => items.length < 4,
        empty: const Center(
          child: Text('Log at least 4 species in your life list to play.'),
        ),
        data: (pool) {
          if (_question == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _nextQuestion(pool);
            });
          }

          return Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Round $_round · Score $_score'),
                const SizedBox(height: AppSpacing.lg),
                if (_question != null)
                  Text(
                    'Which species is this?',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                const SizedBox(height: AppSpacing.md),
                ..._choices.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: OutlinedButton(
                      onPressed: _feedback != null
                          ? null
                          : () => _answer(c),
                      child: Text(c['common_name'] as String? ?? c['scientific_name'] as String),
                    ),
                  ),
                ),
                if (_feedback != null) ...[
                  Text(_feedback!, style: const TextStyle(color: AppColors.accent)),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: () => _nextQuestion(pool),
                    child: const Text('Next'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
