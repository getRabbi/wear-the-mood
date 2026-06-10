import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/profile_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'avatar_service.dart';

/// Avatar + body-data capture (CLAUDE.md §1, §10). Gated behind explicit
/// biometric consent; the selfie goes to the private `avatars` bucket and feeds
/// try-on. Body data is minimized (height + coarse body type).
const biometricConsentVersion = '1.0';

class AvatarScreen extends ConsumerStatefulWidget {
  const AvatarScreen({super.key});

  @override
  ConsumerState<AvatarScreen> createState() => _AvatarScreenState();
}

class _AvatarScreenState extends ConsumerState<AvatarScreen> {
  final _heightController = TextEditingController();
  Uint8List? _newAvatar;
  String? _bodyType;
  bool _busy = false;
  bool _initialised = false;

  @override
  void dispose() {
    _heightController.dispose();
    super.dispose();
  }

  // Pre-fill the form once from the loaded profile.
  void _prime(Profile profile) {
    if (_initialised) return;
    _initialised = true;
    _bodyType = profile.bodyData?.bodyType;
    final h = profile.bodyData?.heightCm;
    if (h != null) _heightController.text = '$h';
  }

  List<({String value, String label})> _bodyTypes(AppLocalizations l10n) => [
    (value: 'Slim', label: l10n.avatarBodySlim),
    (value: 'Average', label: l10n.avatarBodyAverage),
    (value: 'Athletic', label: l10n.avatarBodyAthletic),
    (value: 'Curvy', label: l10n.avatarBodyCurvy),
    (value: 'Plus', label: l10n.avatarBodyPlus),
  ];

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _agree() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .recordConsent(type: 'biometric', version: biometricConsentVersion);
      ref.invalidate(profileProvider);
    } on ApiException {
      _snack(l10n.avatarConsentError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    try {
      final bytes = await ref
          .read(avatarServiceProvider)
          .pickAndCompress(source);
      if (bytes != null && mounted) setState(() => _newAvatar = bytes);
    } catch (_) {
      _snack(l10n.addItemPickError);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      String? avatarPath;
      final bytes = _newAvatar;
      if (bytes != null) {
        avatarPath = await ref.read(avatarServiceProvider).upload(bytes);
      }
      final height = int.tryParse(_heightController.text.trim());
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(
            avatarUrl: avatarPath,
            bodyData: BodyData(heightCm: height, bodyType: _bodyType),
          );
      ref.invalidate(profileProvider);
      ref.invalidate(avatarSignedUrlProvider);
      if (!mounted) return;
      _snack(l10n.avatarSaved);
      setState(() => _newAvatar = null);
    } on ApiException {
      _snack(l10n.avatarError);
    } catch (_) {
      _snack(l10n.avatarError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.avatarTitle)),
      body: SafeArea(
        child: profileAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorState(
            title: l10n.avatarLoadError,
            onRetry: () => ref.invalidate(profileProvider),
            retryLabel: l10n.commonRetry,
          ),
          data: (profile) {
            _prime(profile);
            if (!profile.biometricConsent) {
              return _ConsentGate(busy: _busy, onAgree: _agree);
            }
            return _Form(
              newAvatar: _newAvatar,
              heightController: _heightController,
              bodyType: _bodyType,
              bodyTypes: _bodyTypes(l10n),
              busy: _busy,
              onCamera: () => _pick(ImageSource.camera),
              onGallery: () => _pick(ImageSource.gallery),
              onBodyType: (v) => setState(() => _bodyType = v),
              onSave: _save,
            );
          },
        ),
      ),
    );
  }
}

class _ConsentGate extends StatelessWidget {
  const _ConsentGate({required this.busy, required this.onAgree});

  final bool busy;
  final VoidCallback onAgree;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    size: 56,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Text(
                    l10n.avatarConsentTitle,
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(
                    l10n.avatarConsentBody,
                    style: text.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          PrimaryButton(
            label: l10n.avatarConsentAgree,
            icon: Icons.check_rounded,
            isLoading: busy,
            onPressed: onAgree,
          ),
        ],
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({
    required this.newAvatar,
    required this.heightController,
    required this.bodyType,
    required this.bodyTypes,
    required this.busy,
    required this.onCamera,
    required this.onGallery,
    required this.onBodyType,
    required this.onSave,
  });

  final Uint8List? newAvatar;
  final TextEditingController heightController;
  final String? bodyType;
  final List<({String value, String label})> bodyTypes;
  final bool busy;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final void Function(String? value) onBodyType;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            Center(child: _AvatarPreview(newAvatar: newAvatar)),
            const SizedBox(height: AppSpace.md),
            Center(
              child: Wrap(
                spacing: AppSpace.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: onCamera,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(l10n.addItemCamera),
                  ),
                  OutlinedButton.icon(
                    onPressed: onGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(l10n.addItemGallery),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            TextField(
              controller: heightController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.avatarHeightLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              l10n.avatarBodyTypeLabel,
              style: text.labelLarge?.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final t in bodyTypes)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: bodyType == t.value,
                    onSelected: (sel) => onBodyType(sel ? t.value : null),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
            PrimaryButton(
              label: l10n.avatarSave,
              icon: Icons.check_rounded,
              isLoading: busy,
              onPressed: onSave,
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              l10n.avatarPrivacyNote,
              style: text.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        if (busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

class _AvatarPreview extends ConsumerWidget {
  const _AvatarPreview({required this.newAvatar});

  final Uint8List? newAvatar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const size = 160.0;
    final bytes = newAvatar;
    if (bytes != null) {
      return ClipOval(
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    final signed = ref.watch(avatarSignedUrlProvider);
    return signed.maybeWhen(
      data: (url) => url == null
          ? const _AvatarPlaceholder(size: size)
          : ClipOval(
              child: CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, _) => const _AvatarPlaceholder(size: size),
                errorWidget: (_, _, _) => const _AvatarPlaceholder(size: size),
              ),
            ),
      orElse: () => const _AvatarPlaceholder(size: size),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.accentSoft,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.person_outline,
        size: 56,
        color: AppColors.accent,
      ),
    );
  }
}
