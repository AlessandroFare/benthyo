import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/supabase/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_scaffold.dart';
import 'auth_messages.dart';
import 'auth_providers.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  CertLevel _level = CertLevel.ow;
  CertAgency _agency = CertAgency.padi;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final profile = await ref.read(userProfileProvider.future);
      if (profile != null && mounted && _usernameController.text.isEmpty) {
        _usernameController.text = profile.username;
      }
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).updateProfile(
            userId: user.id,
            username: _usernameController.text.trim(),
            bio: _bioController.text.trim().isEmpty
                ? null
                : _bioController.text.trim(),
            certificationLevel: _level.dbValue,
            certificationAgency: _agency.dbValue,
          );
      ref.invalidate(userProfileProvider);
      if (!mounted) return;
      context.go('/map');
    } catch (e) {
      setState(() => _error = friendlyAuthMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Set up profile',
      showBack: false,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tell us about your diving',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (v) {
                  if (v == null || v.length < 3) return 'Min 3 characters';
                  if (v.startsWith('user_')) return 'Choose a custom username';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _bioController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Bio (optional)'),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<CertLevel>(
                initialValue: _level,
                decoration:
                    const InputDecoration(labelText: 'Certification level'),
                items: CertLevel.values
                    .map(
                      (l) => DropdownMenuItem(
                        value: l,
                        child: Text(l.dbValue),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _level = v ?? CertLevel.ow),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<CertAgency>(
                initialValue: _agency,
                decoration: const InputDecoration(labelText: 'Agency'),
                items: CertAgency.values
                    .map(
                      (a) => DropdownMenuItem(
                        value: a,
                        child: Text(a.dbValue),
                      ),
                    )
                    .toList(),
                onChanged: (v) =>
                    setState(() => _agency = v ?? CertAgency.padi),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
