import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/profile.dart';
import '../../data/models/tryon_photo.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/tryon_photos_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../tryon/sample_garments.dart';
import 'avatar_service.dart';
import 'pose_validator.dart';

/// Try-on photos + body-data capture (CLAUDE.md §1, §10). Gated behind explicit
/// biometric consent. The user keeps a GALLERY of validated full-body photos (each
/// scored on-device) and picks which one is active; that one feeds try-on. We also
/// collect richer body data, so the consent version is bumped.
const biometricConsentVersion = '2.0';

/// A `(value, label)` choice used by the chip groups below.
typedef _Choice = ({String value, String label});

class AvatarScreen extends ConsumerWidget {
  const AvatarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.avatarTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.commonDone),
          ),
        ],
      ),
      body: SafeArea(
        child: profileAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorState(
            title: l10n.avatarLoadError,
            onRetry: () => ref.invalidate(profileProvider),
            retryLabel: l10n.commonRetry,
          ),
          data: (profile) => profile.biometricConsent
              ? _BodyForm(profile: profile)
              : _ConsentGate(profile: profile),
        ),
      ),
    );
  }
}

class _ConsentGate extends ConsumerStatefulWidget {
  const _ConsentGate({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends ConsumerState<_ConsentGate> {
  bool _busy = false;

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
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.avatarConsentError)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
            isLoading: _busy,
            onPressed: _agree,
          ),
        ],
      ),
    );
  }
}

class _BodyForm extends ConsumerStatefulWidget {
  const _BodyForm({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_BodyForm> createState() => _BodyFormState();
}

class _BodyFormState extends ConsumerState<_BodyForm> {
  final _cmController = TextEditingController();
  final _ftController = TextEditingController();
  final _inController = TextEditingController();
  final _weightController = TextEditingController();

  // Body details (single source of truth; height is always stored in cm).
  String? _gender;
  int? _heightCm;
  bool _useFtIn = false;
  int? _weightKg;
  String? _ageRange;
  String? _bodyType;
  String? _fitPreference;
  String? _skinTone;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final b = widget.profile.bodyData;
    _gender = b?.gender;
    _heightCm = b?.heightCm;
    _weightKg = b?.weightKg;
    _ageRange = b?.ageRange;
    _bodyType = b?.bodyType;
    _fitPreference = b?.fitPreference;
    _skinTone = b?.skinTone;
    _weightController.text = _weightKg?.toString() ?? '';
    _syncHeightControllers();
  }

  @override
  void dispose() {
    _cmController.dispose();
    _ftController.dispose();
    _inController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  // ---- height helpers (canonical cm <-> ft/in) ----------------------------

  void _syncHeightControllers() {
    final cm = _heightCm;
    if (_useFtIn) {
      if (cm == null) {
        _ftController.text = '';
        _inController.text = '';
      } else {
        final totalInches = (cm / 2.54).round();
        _ftController.text = '${totalInches ~/ 12}';
        _inController.text = '${totalInches % 12}';
      }
    } else {
      _cmController.text = cm?.toString() ?? '';
    }
  }

  void _onCmChanged(String v) => _heightCm = int.tryParse(v.trim());

  void _onFtInChanged() {
    final ft = int.tryParse(_ftController.text.trim()) ?? 0;
    final inch = int.tryParse(_inController.text.trim()) ?? 0;
    _heightCm = (ft == 0 && inch == 0)
        ? null
        : (ft * 30.48 + inch * 2.54).round();
  }

  Future<void> _save() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(
            bodyData: BodyData(
              gender: _gender,
              heightCm: _heightCm,
              weightKg: _weightKg,
              ageRange: _ageRange,
              bodyType: _bodyType,
              fitPreference: _fitPreference,
              skinTone: _skinTone,
            ),
          );
      ref.invalidate(profileProvider);
      if (!mounted) return;
      _snack(l10n.avatarSaved);
    } on ApiException {
      _snack(l10n.avatarError);
    } catch (_) {
      _snack(l10n.avatarError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- choices -------------------------------------------------------------

  List<_Choice> _genders(AppLocalizations l) => [
    (value: 'female', label: l.avatarGenderFemale),
    (value: 'male', label: l.avatarGenderMale),
  ];

  List<_Choice> _bodyTypes(AppLocalizations l) {
    final base = <_Choice>[
      (value: 'Slim', label: l.avatarBodySlim),
      (value: 'Average', label: l.avatarBodyAverage),
      (value: 'Athletic', label: l.avatarBodyAthletic),
      (value: 'Petite', label: l.avatarBodyPetite),
      (value: 'Tall', label: l.avatarBodyTall),
      (value: 'Plus', label: l.avatarBodyPlus),
      (value: 'Rectangle', label: l.avatarBodyRectangle),
    ];
    final female = <_Choice>[
      (value: 'Curvy', label: l.avatarBodyCurvy),
      (value: 'Hourglass', label: l.avatarBodyHourglass),
      (value: 'Pear', label: l.avatarBodyPear),
      (value: 'Apple', label: l.avatarBodyApple),
    ];
    final male = <_Choice>[
      (value: 'Muscular', label: l.avatarBodyMuscular),
      (value: 'Broad', label: l.avatarBodyBroad),
      (value: 'Lean', label: l.avatarBodyLean),
      (value: 'Stocky', label: l.avatarBodyStocky),
    ];
    return switch (_gender) {
      'female' => [...base, ...female],
      'male' => [...base, ...male],
      _ => [...base, ...female, ...male],
    };
  }

  List<_Choice> _fits(AppLocalizations l) => [
    (value: 'slim', label: l.avatarFitSlim),
    (value: 'regular', label: l.avatarFitRegular),
    (value: 'relaxed', label: l.avatarFitRelaxed),
  ];

  List<_Choice> _ages(AppLocalizations l) => [
    (value: 'under_18', label: l.avatarAgeUnder18),
    (value: '18_24', label: l.avatarAge1824),
    (value: '25_34', label: l.avatarAge2534),
    (value: '35_44', label: l.avatarAge3544),
    (value: '45_54', label: l.avatarAge4554),
    (value: '55_plus', label: l.avatarAge55Plus),
  ];

  List<_Choice> _skinTones(AppLocalizations l) => [
    (value: 'fair', label: l.avatarSkinFair),
    (value: 'light', label: l.avatarSkinLight),
    (value: 'medium', label: l.avatarSkinMedium),
    (value: 'olive', label: l.avatarSkinOlive),
    (value: 'brown', label: l.avatarSkinBrown),
    (value: 'deep', label: l.avatarSkinDeep),
  ];

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            _SectionTitle(l10n.avatarSectionPhoto),
            const SizedBox(height: AppSpace.sm),
            _PhotoGuide(),
            const SizedBox(height: AppSpace.md),
            const _TryOnGallery(),

            const SizedBox(height: AppSpace.xl),
            _SectionTitle(l10n.avatarSectionBody),
            const SizedBox(height: AppSpace.sm),

            _chipGroup(
              label: l10n.avatarGenderLabel,
              options: _genders(l10n),
              selected: _gender,
              onChanged: (v) => setState(() => _gender = v),
            ),
            const SizedBox(height: AppSpace.lg),

            _HeightField(
              useFtIn: _useFtIn,
              cmController: _cmController,
              ftController: _ftController,
              inController: _inController,
              onCmChanged: _onCmChanged,
              onFtInChanged: _onFtInChanged,
              onToggle: (ftIn) => setState(() {
                _useFtIn = ftIn;
                _syncHeightControllers();
              }),
            ),
            const SizedBox(height: AppSpace.lg),

            _chipGroup(
              label: l10n.avatarBodyTypeLabel,
              options: _bodyTypes(l10n),
              selected: _bodyType,
              onChanged: (v) => setState(() => _bodyType = v),
            ),
            const SizedBox(height: AppSpace.lg),

            _chipGroup(
              label: l10n.avatarFitLabel,
              options: _fits(l10n),
              selected: _fitPreference,
              onChanged: (v) => setState(() => _fitPreference = v),
            ),

            const SizedBox(height: AppSpace.xl),
            Text(
              l10n.avatarOptionalNote,
              style: text.bodySmall?.copyWith(color: AppColors.graphite),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _weightController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) => _weightKg = int.tryParse(v.trim()),
              decoration: InputDecoration(
                labelText: l10n.avatarWeightLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            _chipGroup(
              label: l10n.avatarAgeLabel,
              options: _ages(l10n),
              selected: _ageRange,
              onChanged: (v) => setState(() => _ageRange = v),
            ),
            const SizedBox(height: AppSpace.lg),
            _chipGroup(
              label: l10n.avatarSkinToneLabel,
              options: _skinTones(l10n),
              selected: _skinTone,
              onChanged: (v) => setState(() => _skinTone = v),
            ),

            const SizedBox(height: AppSpace.xl),
            PrimaryButton(
              label: l10n.avatarSave,
              icon: Icons.check_rounded,
              isLoading: _busy,
              onPressed: _save,
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              l10n.avatarPrivacyNote,
              style: text.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _chipGroup({
    required String label,
    required List<_Choice> options,
    required String? selected,
    required ValueChanged<String?> onChanged,
  }) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelLarge?.copyWith(color: AppColors.graphite)),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final o in options)
              ChoiceChip(
                label: Text(o.label),
                selected: selected == o.value,
                onSelected: (sel) => onChanged(sel ? o.value : null),
              ),
          ],
        ),
      ],
    );
  }
}

/// The try-on photo gallery — saved photos (each with a quality score) plus an
/// "Add photo" tile. Tap selects the active one; long-press deletes.
class _TryOnGallery extends ConsumerStatefulWidget {
  const _TryOnGallery();

  @override
  ConsumerState<_TryOnGallery> createState() => _TryOnGalleryState();
}

class _TryOnGalleryState extends ConsumerState<_TryOnGallery> {
  bool _busy = false; // add / select / delete in flight

  String? _issueMessage(AppLocalizations l, PoseIssue issue) => switch (issue) {
    PoseIssue.none => null,
    PoseIssue.noPerson => l.avatarCheckNoPerson,
    PoseIssue.headNotVisible => l.avatarCheckHead,
    PoseIssue.feetNotVisible => l.avatarCheckFeet,
  };

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add(ImageSource source) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final file = await ref.read(avatarServiceProvider).pick(source);
      if (file == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final result = await ref
          .read(poseValidatorProvider)
          .inspectFile(file.path);
      if (!result.check.ok) {
        _snack(_issueMessage(l10n, result.check.issue) ?? l10n.avatarCheckFailGeneric);
        if (mounted) setState(() => _busy = false);
        return;
      }
      final bytes = await ref.read(avatarServiceProvider).compress(file);
      final path = await ref.read(avatarServiceProvider).uploadTryonPhoto(bytes);
      await ref
          .read(tryonPhotosRepositoryProvider)
          .add(storagePath: path, qualityScore: result.score);
      ref.invalidate(tryonPhotosProvider);
      ref.invalidate(avatarSignedUrlProvider); // first photo auto-selects
      ref.invalidate(profileProvider);
    } on ApiException {
      _snack(l10n.avatarCheckFailGeneric);
    } catch (_) {
      _snack(l10n.addItemPickError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select(TryonPhoto photo) async {
    if (_busy || photo.isSelected) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(avatarUrl: photo.storagePath);
      ref.invalidate(tryonPhotosProvider);
      ref.invalidate(avatarSignedUrlProvider);
      ref.invalidate(profileProvider);
    } catch (_) {
      // best-effort; gallery stays as-is
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(TryonPhoto photo) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.avatarPhotoDeleteTitle),
        content: Text(l10n.avatarPhotoDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.profileCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.profileDeleteAccount),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(tryonPhotosRepositoryProvider).delete(photo.id);
      ref.invalidate(tryonPhotosProvider);
      ref.invalidate(avatarSignedUrlProvider);
      ref.invalidate(profileProvider);
      _snack(l10n.avatarPhotoDeleted);
    } catch (_) {
      _snack(l10n.avatarPhotoDeleteError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickSource() async {
    final l10n = AppLocalizations.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.addItemCamera),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.addItemGallery),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _add(source);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final photosAsync = ref.watch(tryonPhotosProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.avatarGalleryHint,
          style: text.bodySmall?.copyWith(color: AppColors.graphite),
        ),
        const SizedBox(height: AppSpace.md),
        photosAsync.when(
          skipLoadingOnReload: true,
          loading: () => const SizedBox(
            height: 150,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => _AddTile(busy: _busy, onTap: _pickSource),
          data: (photos) => Wrap(
            spacing: AppSpace.md,
            runSpacing: AppSpace.md,
            children: [
              for (final p in photos)
                _PhotoTile(
                  photo: p,
                  onTap: () => _select(p),
                  onLongPress: () => _delete(p),
                  onDelete: () => _delete(p),
                ),
              _AddTile(busy: _busy, onTap: _pickSource),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhotoTile extends ConsumerWidget {
  const _PhotoTile({
    required this.photo,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
  });

  final TryonPhoto photo;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  static const _w = 104.0;
  static const _h = 140.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final signed = ref.watch(tryonPhotoSignedUrlProvider(photo.storagePath));
    final url = signed.asData?.value;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: _w,
        height: _h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: url == null
                  ? const ColoredBox(color: AppColors.mist)
                  : CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          const ColoredBox(color: AppColors.mist),
                      errorWidget: (_, _, _) =>
                          const ColoredBox(color: AppColors.mist),
                    ),
            ),
            // Selected ring.
            if (photo.isSelected)
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.accent, width: 3),
                ),
              ),
            // Quality score badge (bottom-left).
            if (photo.qualityScore != null)
              Positioned(
                left: 4,
                bottom: 4,
                child: _Badge(
                  l10n.avatarQualityBadge(photo.qualityScore!),
                  color: const Color(0xCC000000),
                ),
              ),
            // Active badge (top-right).
            if (photo.isSelected)
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.accent,
                  size: 22,
                ),
              ),
            // Visible delete (top-left) — also available via long-press.
            Positioned(
              top: 2,
              left: 2,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xCC000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 104,
        height: 140,
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Center(
          child: busy
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_a_photo_outlined,
                      color: AppColors.accent,
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(l10n.avatarGalleryAdd, style: text.bodySmall),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _PhotoGuide extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final dos = [
      l10n.avatarGuideDo1,
      l10n.avatarGuideDo2,
      l10n.avatarGuideDo3,
      l10n.avatarGuideDo4,
      l10n.avatarGuideDo5,
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 84,
              height: 112,
              child: CachedNetworkImage(
                imageUrl: samplePersonImageUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => const ColoredBox(color: AppColors.mist),
                errorWidget: (_, _, _) => const ColoredBox(
                  color: AppColors.mist,
                  child: Icon(Icons.person_outline, color: AppColors.accent),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.avatarGuideTitle, style: text.titleMedium),
                const SizedBox(height: AppSpace.xs),
                Text(l10n.avatarGuideSubtitle, style: text.bodySmall),
                const SizedBox(height: AppSpace.sm),
                for (final d in dos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: AppSpace.xs),
                        Expanded(child: Text(d, style: text.bodySmall)),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  l10n.avatarGuideDont,
                  style: text.bodySmall?.copyWith(color: AppColors.danger),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeightField extends StatelessWidget {
  const _HeightField({
    required this.useFtIn,
    required this.cmController,
    required this.ftController,
    required this.inController,
    required this.onCmChanged,
    required this.onFtInChanged,
    required this.onToggle,
  });

  final bool useFtIn;
  final TextEditingController cmController;
  final TextEditingController ftController;
  final TextEditingController inController;
  final ValueChanged<String> onCmChanged;
  final VoidCallback onFtInChanged;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.avatarHeightLabel,
              style: text.labelLarge?.copyWith(color: AppColors.graphite),
            ),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(l10n.avatarHeightUnitCm)),
                ButtonSegment(value: true, label: Text(l10n.avatarHeightUnitFt)),
              ],
              selected: {useFtIn},
              onSelectionChanged: (s) => onToggle(s.first),
              showSelectedIcon: false,
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        if (!useFtIn)
          TextField(
            controller: cmController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: onCmChanged,
            decoration: InputDecoration(
              suffixText: l10n.avatarHeightUnitCm,
              border: const OutlineInputBorder(),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: ftController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => onFtInChanged(),
                  decoration: InputDecoration(
                    suffixText: l10n.avatarHeightFeet,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: TextField(
                  controller: inController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => onFtInChanged(),
                  decoration: InputDecoration(
                    suffixText: l10n.avatarHeightInches,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
