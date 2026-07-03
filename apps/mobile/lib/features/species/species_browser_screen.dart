import 'dart:async' show unawaited;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import '../../core/widgets/main_navigation.dart';
import 'species_providers.dart';

class SpeciesBrowserScreen extends ConsumerStatefulWidget {
  const SpeciesBrowserScreen({super.key});

  @override
  ConsumerState<SpeciesBrowserScreen> createState() =>
      _SpeciesBrowserScreenState();
}

class _SpeciesBrowserScreenState extends ConsumerState<SpeciesBrowserScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openIdentify() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      context.push('/species/identify?q=${Uri.encodeComponent(query)}');
    } else {
      context.push('/species/identify');
    }
  }

  Future<void> _identifyFromPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null || !mounted) return;
    unawaited(
      context.push(
        '/species/identify?path=${Uri.encodeComponent(file.path)}',
      ),
    );
  }

  Future<void> _identifyFromGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null || !mounted) return;
    unawaited(
      context.push(
        '/species/identify?path=${Uri.encodeComponent(file.path)}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final speciesAsync = _query.isEmpty
        ? ref.watch(speciesListProvider)
        : ref.watch(speciesSearchProvider(_query));

    return AppScaffold(
      title: 'Species',
      showBack: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.photo_camera_outlined),
          onPressed: _identifyFromPhoto,
        ),
        IconButton(
          icon: const Icon(Icons.photo_library_outlined),
          onPressed: _identifyFromGallery,
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Identify species...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
              onSubmitted: (_) => _openIdentify(),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
          ),
          Expanded(
            child: AsyncValueWidget(
              value: speciesAsync,
              isEmpty: (list) => list.isEmpty,
              empty: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('No species match your search'),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: _identifyFromPhoto,
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Identify from photo'),
                    ),
                  ],
                ),
              ),
              data: (species) => ListView.separated(
                itemCount: species.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final s = species[index];
                  return ListTile(
                    minVerticalPadding: AppSpacing.sm,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: s.imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: s.imageUrl!,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 56,
                              height: 56,
                              color: AppColors.surfaceDark,
                              child: const Icon(Icons.pets),
                            ),
                    ),
                    title: Text(
                      s.displayName(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      s.scientificName,
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/species/${s.id}'),
                  );
                },
              ),
            ),
          ),
          const MainNavigationBar(currentIndex: 3),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _identifyFromPhoto,
        icon: const Icon(Icons.photo_camera),
        label: const Text('Identify'),
      ),
    );
  }
}
