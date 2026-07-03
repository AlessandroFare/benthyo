import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/enums.dart';
import '../../core/ml/clip_providers.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/async_value_widget.dart';
import '../dive_sites/dive_sites_providers.dart';
import '../species/species_providers.dart';
import '../uploads/uploads_repository.dart';
import 'sightings_providers.dart';

class AddSightingScreen extends ConsumerStatefulWidget {
  const AddSightingScreen({
    super.key,
    this.initialSiteId,
    this.initialSpeciesId,
    this.initialPhotoUrl,
  });

  final String? initialSiteId;
  final String? initialSpeciesId;
  final String? initialPhotoUrl;

  @override
  ConsumerState<AddSightingScreen> createState() => _AddSightingScreenState();
}

class _AddSightingScreenState extends ConsumerState<AddSightingScreen> {
  String? _siteId;
  String? _speciesId;
  ConfidenceLevel _confidence = ConfidenceLevel.likely;
  final _depthController = TextEditingController();
  final _countController = TextEditingController(text: '1');
  final _notesController = TextEditingController();
  final _picker = ImagePicker();

  final List<File> _pendingPhotos = [];
  final List<String> _uploadedUrls = [];
  final Map<String, File> _urlToLocalFile = {};
  bool _uploading = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _siteId = widget.initialSiteId;
    _speciesId = widget.initialSpeciesId;
    if (widget.initialPhotoUrl != null && widget.initialPhotoUrl!.isNotEmpty) {
      _uploadedUrls.add(widget.initialPhotoUrl!);
    }
  }

  @override
  void dispose() {
    _depthController.dispose();
    _countController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _addPhoto(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        // Spec: client-side resize before upload (techstack_zero_budget.md
        // section 4 "Image processing").
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked == null) return;
      setState(() => _pendingPhotos.add(File(picked.path)));
    } on Exception catch (e) {
      setState(() => _error = 'Photo picker error: $e');
    }
  }

  Future<List<String>> _uploadPendingPhotos() async {
    if (_pendingPhotos.isEmpty) return _uploadedUrls;
    setState(() => _uploading = true);
    try {
      for (final file in _pendingPhotos) {
        final url = await ref.read(uploadSightingPhotoProvider(file).future);
        _uploadedUrls.add(url);
        _urlToLocalFile[url] = file;
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
    return _uploadedUrls;
  }

  Future<void> _submit() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    if (_siteId == null || _speciesId == null) {
      setState(() => _error = 'Select a dive site and species');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Upload any pending photos first. If we're offline the upload will
      // fail; we still let the user save the sighting — they'll just see
      // an explanatory error and can retry when online.
      final urls = await _uploadPendingPhotos();

      final sighting = await ref.read(sightingsRepositoryProvider).create(
            userId: user.id,
            diveSiteId: _siteId!,
            speciesId: _speciesId!,
            observedAt: DateTime.now(),
            confidence: _confidence,
            count: int.tryParse(_countController.text) ?? 1,
            depthM: double.tryParse(_depthController.text),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            photoUrls: urls,
            isOnline: await ref.read(isOnlineProvider.future),
          );

      // Fan uploaded photo URLs out to the normalized `sighting_photos` table.
      // This runs best-effort: if the insert fails (e.g. offline), the
      // photo_urls column on the sighting row acts as the fallback source of
      // truth and the back-fill trigger will catch them on next insert.
      if (urls.isNotEmpty) {
        final repo = ref.read(sightingsRepositoryProvider);
        for (var i = 0; i < urls.length; i++) {
          try {
            await repo.addPhoto(
              sightingId: sighting.id,
              userId: user.id,
              storagePath: urls[i],
              publicUrl: urls[i],
              sortOrder: i,
            );
          } catch (_) {
            // Non-blocking — sighting is already saved.
          }
        }
      }

      final token =
          ref.read(supabaseClientProvider).auth.currentSession?.accessToken;
      if (token != null && urls.isNotEmpty) {
        final embedRepo = ref.read(photoEmbeddingRepositoryProvider);
        for (final url in urls) {
          final file = _urlToLocalFile[url];
          if (file != null) {
            try {
              await embedRepo.registerPhoto(
                bytes: await file.readAsBytes(),
                accessToken: token,
                sightingId: sighting.id,
                photoUrl: url,
                speciesId: _speciesId,
              );
            } catch (_) {
              // Non-blocking — sighting saved even if embedding upload fails.
            }
          }
        }
      }
      ref.invalidate(sightingsFeedProvider);
      ref.invalidate(userSightingsProvider);
      if (!mounted) return;
      context.pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sitesAsync = ref.watch(diveSitesProvider);
    final speciesAsync = ref.watch(speciesListProvider);

    return AppScaffold(
      title: 'Report Sighting',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AsyncValueWidget(
              value: sitesAsync,
              data: (sites) => DropdownButtonFormField<String>(
                value: _siteId,
                decoration: const InputDecoration(labelText: 'Dive site'),
                items: sites
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(s.name),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _siteId = v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AsyncValueWidget(
              value: speciesAsync,
              data: (species) => DropdownButtonFormField<String>(
                value: _speciesId,
                decoration: const InputDecoration(labelText: 'Species'),
                items: species
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(s.displayName()),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _speciesId = v),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<ConfidenceLevel>(
              value: _confidence,
              decoration: const InputDecoration(labelText: 'Confidence'),
              items: ConfidenceLevel.values
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(c.dbValue),
                    ),
                  )
                  .toList(),
              onChanged: (v) =>
                  setState(() => _confidence = v ?? ConfidenceLevel.likely),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _countController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Count'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _depthController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Depth (m)'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: AppSpacing.md),
            _PhotoStrip(
              photos: _pendingPhotos,
              onAdd: () => _showPhotoSourceSheet(),
              onRemove: (i) => setState(() => _pendingPhotos.removeAt(i)),
            ),
            if (_uploading) ...[
              const SizedBox(height: AppSpacing.sm),
              const LinearProgressIndicator(),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Uploading photos…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: (_loading || _uploading) ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit sighting'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _addPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Pick from gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _addPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.photos,
    required this.onAdd,
    required this.onRemove,
  });

  final List<File> photos;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index == photos.length) {
            return InkWell(
              onTap: onAdd,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.add_a_photo, color: Colors.white70),
              ),
            );
          }
          final file = photos[index];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  file,
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minHeight: 24,
                    minWidth: 24,
                  ),
                  onPressed: () => onRemove(index),
                  icon: const CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
