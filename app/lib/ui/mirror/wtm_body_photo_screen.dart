import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/media/image_pick_permission.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/profile.dart';
import '../../data/models/studio_model_preset.dart';
import '../../data/models/tryon_photo.dart';
import '../../data/repositories/ai_studio_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/tryon_photos_repository.dart';
import '../../features/profile/avatar_screen.dart' show biometricConsentVersion;
import '../../features/profile/avatar_service.dart';
import '../../features/profile/pose_validator.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_body_source.dart';

/// A `(value, label)` choice used by the chip groups.
typedef _Choice = ({String value, String label});

const _tileW = 104.0;
const _tileH = 138.0;

/// WTM Atelier "Body & Try-On" manager (Fix 2 + Fix 5) — the restyled body-photo
/// page reached from MoodMirror Step 1's portal / "Update photo". Keeps every bit
/// of the original avatar flow (consent gate, gallery add/select/delete, body
/// data) on the real providers, and adds the studio-model / mannequin body picker
/// (§ Try-On Body System). Consent-gated (§10) — capture never bypasses it.
class WtmBodyPhotoScreen extends ConsumerWidget {
  const WtmBodyPhotoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(profileProvider);

    return profileAsync.when(
      skipLoadingOnReload: true,
      loading: () => WtmPage(
        title: l10n.avatarTitle,
        children: const [
          LoadingShimmer(
            width: double.infinity,
            height: 260,
            borderRadius: WtmRadius.arch,
          ),
        ],
      ),
      error: (_, _) => WtmPage(
        title: l10n.avatarTitle,
        children: [
          WtmErrorState(
            title: l10n.avatarLoadError,
            message: l10n.errorGenericTitle,
            retryLabel: l10n.commonRetry,
            onRetry: () => ref.invalidate(profileProvider),
          ),
        ],
      ),
      data: (profile) => profile.biometricConsent
          ? _BodyManager(profile: profile)
          : _ConsentGate(profile: profile),
    );
  }
}

/// Consent gate (§10) — biometric consent before any body capture, WTM-styled.
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
      if (mounted) wtmSnack(context, l10n.avatarConsentError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WtmPage(
      title: l10n.avatarTitle,
      footer: GradientCta(
        label: l10n.avatarConsentAgree,
        icon: const WtmIcon(WtmGlyph.check, size: 15, color: WtmColors.ctaText),
        onPressed: _busy ? null : _agree,
      ),
      children: [
        const SizedBox(height: WtmSpace.s22),
        Center(
          child: SizedBox(
            width: 132,
            height: 210,
            child: AuroraBox(
              borderRadius: WtmRadius.arch,
              vignette: true,
              child: const Center(
                child: SizedBox(
                  width: 96,
                  height: 190,
                  child: WtmFigure(WtmFigureKind.body, opacity: 0.85),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: WtmSpace.s22),
        Text(
          l10n.avatarConsentTitle,
          textAlign: TextAlign.center,
          style: WtmType.h2.copyWith(fontSize: 20),
        ),
        const SizedBox(height: WtmSpace.s10),
        Text(
          l10n.avatarConsentBody,
          textAlign: TextAlign.center,
          style: WtmType.sub.copyWith(height: 1.55),
        ),
      ],
    );
  }
}

/// The full manager: try-on body preview + photo gallery + model/mannequin picker
/// + body-details form, over a sticky Save footer.
class _BodyManager extends ConsumerStatefulWidget {
  const _BodyManager({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_BodyManager> createState() => _BodyManagerState();
}

class _BodyManagerState extends ConsumerState<_BodyManager> {
  final _cm = TextEditingController();
  final _ft = TextEditingController();
  final _in = TextEditingController();
  final _weight = TextEditingController();

  String? _gender;
  int? _heightCm;
  bool _useFtIn = false;
  int? _weightKg;
  String? _ageRange;
  String? _bodyType;
  String? _fitPreference;
  String? _skinTone;

  bool _saving = false; // body-data save
  bool _photoBusy = false; // gallery add / select / delete

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
    _weight.text = _weightKg?.toString() ?? '';
    _syncHeight();
  }

  @override
  void dispose() {
    _cm.dispose();
    _ft.dispose();
    _in.dispose();
    _weight.dispose();
    super.dispose();
  }

  // ---- height helpers (canonical cm <-> ft/in) -----------------------------
  void _syncHeight() {
    final cm = _heightCm;
    if (_useFtIn) {
      if (cm == null) {
        _ft.text = '';
        _in.text = '';
      } else {
        final total = (cm / 2.54).round();
        _ft.text = '${total ~/ 12}';
        _in.text = '${total % 12}';
      }
    } else {
      _cm.text = cm?.toString() ?? '';
    }
  }

  void _onFtIn() {
    final ft = int.tryParse(_ft.text.trim()) ?? 0;
    final inch = int.tryParse(_in.text.trim()) ?? 0;
    _heightCm = (ft == 0 && inch == 0)
        ? null
        : (ft * 30.48 + inch * 2.54).round();
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
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
      if (mounted) wtmSnack(context, l10n.avatarSaved);
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.avatarError);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- gallery actions -----------------------------------------------------
  String? _issue(AppLocalizations l, PoseIssue issue) => switch (issue) {
    PoseIssue.none => null,
    PoseIssue.noPerson => l.avatarCheckNoPerson,
    PoseIssue.headNotVisible => l.avatarCheckHead,
    PoseIssue.feetNotVisible => l.avatarCheckFeet,
  };

  Future<void> _addPhoto(ImageSource source) async {
    if (_photoBusy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _photoBusy = true);
    final svc = ref.read(avatarServiceProvider);
    String? tempPath;
    try {
      final file = await svc.pick(source);
      if (file == null) {
        if (mounted) setState(() => _photoBusy = false);
        return;
      }
      final bytes = await svc.compress(file);
      tempPath = await svc.writeTempJpeg(bytes);
      final result = await ref
          .read(poseValidatorProvider)
          .inspectFile(tempPath);
      if (!result.check.ok) {
        if (mounted) {
          wtmSnack(
            context,
            _issue(l10n, result.check.issue) ?? l10n.avatarCheckFailGeneric,
          );
        }
        if (mounted) setState(() => _photoBusy = false);
        return;
      }
      final media = await svc.uploadTryonPhoto(bytes);
      await ref
          .read(tryonPhotosRepositoryProvider)
          .add(
            storagePath: media.legacyUrl,
            objectKey: media.objectKey,
            qualityScore: result.score,
          );
      ref.read(wtmBodyChoiceProvider.notifier).usePhoto();
      ref.invalidate(tryonPhotosProvider);
      ref.invalidate(avatarSignedUrlProvider);
      ref.invalidate(profileProvider);
    } on ApiException {
      if (mounted) wtmSnack(context, l10n.avatarError);
    } catch (e) {
      if (mounted) {
        if (isImagePermissionDenied(e)) {
          await showImagePermissionHelp(
            context,
            camera: source == ImageSource.camera,
          );
        } else {
          wtmSnack(context, l10n.addItemPickError);
        }
      }
    } finally {
      final tp = tempPath;
      if (tp != null) {
        try {
          await File(tp).delete();
        } catch (_) {
          /* best-effort */
        }
      }
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _pickSource() async {
    final l10n = AppLocalizations.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: WtmColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(WtmRadius.sheetTop),
        ),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: WtmSpace.s8),
            ListTile(
              leading: const WtmIcon(
                WtmGlyph.camera,
                size: 18,
                color: WtmColors.gold,
              ),
              title: Text(l10n.addItemCamera, style: WtmType.body),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const WtmIcon(
                WtmGlyph.image,
                size: 18,
                color: WtmColors.gold,
              ),
              title: Text(l10n.addItemGallery, style: WtmType.body),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: WtmSpace.s8),
          ],
        ),
      ),
    );
    if (source != null) await _addPhoto(source);
  }

  Future<void> _selectPhoto(TryonPhoto photo) async {
    if (_photoBusy) return;
    ref.read(wtmBodyChoiceProvider.notifier).usePhoto();
    if (photo.isSelected) return;
    setState(() => _photoBusy = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(avatarUrl: photo.storagePath);
      ref.invalidate(tryonPhotosProvider);
      ref.invalidate(avatarSignedUrlProvider);
      ref.invalidate(profileProvider);
    } catch (_) {
      /* best-effort — gallery stays as-is */
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _deletePhoto(TryonPhoto photo) async {
    final l10n = AppLocalizations.of(context);
    final ok = await wtmConfirmDialog(
      context,
      title: l10n.avatarPhotoDeleteTitle,
      message: l10n.avatarPhotoDeleteBody,
      confirmLabel: l10n.profileDeleteAccount,
      danger: true,
    );
    if (!ok) return;
    setState(() => _photoBusy = true);
    try {
      await ref.read(tryonPhotosRepositoryProvider).delete(photo.id);
      ref.invalidate(tryonPhotosProvider);
      ref.invalidate(avatarSignedUrlProvider);
      ref.invalidate(profileProvider);
      if (mounted) wtmSnack(context, l10n.avatarPhotoDeleted);
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.avatarPhotoDeleteError);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
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

  List<_Choice> _skins(AppLocalizations l) => [
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
    final photosAsync = ref.watch(tryonPhotosProvider);
    final choice = ref.watch(wtmBodyChoiceProvider);
    final modelsAsync = ref.watch(studioModelsProvider);

    return WtmPage(
      title: l10n.avatarTitle,
      footer: GradientCta(
        label: l10n.avatarSave,
        icon: const WtmIcon(WtmGlyph.check, size: 15, color: WtmColors.ctaText),
        onPressed: _saving ? null : _save,
      ),
      children: [
        // ── Try-on photo gallery ──
        EyebrowLabel(l10n.avatarSectionPhoto),
        const SizedBox(height: WtmSpace.s6),
        Text(l10n.avatarGalleryHint, style: WtmType.micro),
        const SizedBox(height: WtmSpace.s12),
        photosAsync.when(
          skipLoadingOnReload: true,
          loading: () => const LoadingShimmer(
            width: double.infinity,
            height: _tileH,
            borderRadius: BorderRadius.all(Radius.circular(WtmRadius.tile)),
          ),
          error: (_, _) => Align(
            alignment: Alignment.centerLeft,
            child: _AddTile(busy: _photoBusy, onTap: _pickSource),
          ),
          data: (photos) => Wrap(
            spacing: WtmSpace.s10,
            runSpacing: WtmSpace.s10,
            children: [
              for (final p in photos)
                _PhotoTile(
                  photo: p,
                  active: choice is WtmBodyPhoto && p.isSelected,
                  onTap: () => _selectPhoto(p),
                  onDelete: () => _deletePhoto(p),
                ),
              _AddTile(busy: _photoBusy, onTap: _pickSource),
            ],
          ),
        ),

        const SizedBox(height: WtmSpace.s22),

        // ── Model / mannequin picker (Fix 5) ──
        EyebrowLabel(l10n.wtmBodyModelsLabel),
        const SizedBox(height: WtmSpace.s6),
        Text(l10n.wtmBodyModelsHint, style: WtmType.micro),
        const SizedBox(height: WtmSpace.s12),
        Wrap(
          spacing: WtmSpace.s10,
          runSpacing: WtmSpace.s10,
          children: [
            _MannequinTile(
              label: l10n.wtmBodyMannequin,
              active: choice is WtmBodyMannequin,
              onTap: () =>
                  ref.read(wtmBodyChoiceProvider.notifier).useMannequin(),
            ),
            ...modelsAsync.maybeWhen(
              data: (models) => [
                for (final m in models)
                  _ModelTile(
                    model: m,
                    active: choice is WtmBodyModel && choice.model.id == m.id,
                    onTap: () =>
                        ref.read(wtmBodyChoiceProvider.notifier).useModel(m),
                  ),
              ],
              orElse: () => const <Widget>[],
            ),
            if (modelsAsync.asData?.value.isEmpty ?? true)
              _SoonTile(label: l10n.wtmBodyModelsSoon),
          ],
        ),

        const SizedBox(height: WtmSpace.s22),

        // ── Body details ──
        EyebrowLabel(l10n.avatarSectionBody),
        const SizedBox(height: WtmSpace.s12),
        _chips(
          l10n.avatarGenderLabel,
          _genders(l10n),
          _gender,
          (v) => setState(() => _gender = v),
        ),
        const SizedBox(height: WtmSpace.s16),
        _heightRow(l10n),
        const SizedBox(height: WtmSpace.s16),
        _chips(
          l10n.avatarBodyTypeLabel,
          _bodyTypes(l10n),
          _bodyType,
          (v) => setState(() => _bodyType = v),
        ),
        const SizedBox(height: WtmSpace.s16),
        _chips(
          l10n.avatarFitLabel,
          _fits(l10n),
          _fitPreference,
          (v) => setState(() => _fitPreference = v),
        ),
        const SizedBox(height: WtmSpace.s16),
        _field(
          label: l10n.avatarWeightLabel,
          controller: _weight,
          onChanged: (v) => _weightKg = int.tryParse(v.trim()),
        ),
        const SizedBox(height: WtmSpace.s16),
        _chips(
          l10n.avatarAgeLabel,
          _ages(l10n),
          _ageRange,
          (v) => setState(() => _ageRange = v),
        ),
        const SizedBox(height: WtmSpace.s16),
        _chips(
          l10n.avatarSkinToneLabel,
          _skins(l10n),
          _skinTone,
          (v) => setState(() => _skinTone = v),
        ),
      ],
    );
  }

  Widget _chips(
    String label,
    List<_Choice> options,
    String? selected,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: WtmType.label.copyWith(color: WtmColors.muted)),
        const SizedBox(height: WtmSpace.s8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final o in options)
              WtmChip(
                label: o.label,
                on: selected == o.value,
                onTap: () => onChanged(selected == o.value ? null : o.value),
              ),
          ],
        ),
      ],
    );
  }

  Widget _heightRow(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.avatarHeightLabel,
                style: WtmType.label.copyWith(color: WtmColors.muted),
              ),
            ),
            WtmChip(
              label: l10n.avatarHeightUnitCm,
              on: !_useFtIn,
              onTap: () => setState(() {
                _useFtIn = false;
                _syncHeight();
              }),
            ),
            const SizedBox(width: 7),
            WtmChip(
              label: l10n.avatarHeightUnitFt,
              on: _useFtIn,
              onTap: () => setState(() {
                _useFtIn = true;
                _syncHeight();
              }),
            ),
          ],
        ),
        const SizedBox(height: WtmSpace.s8),
        if (!_useFtIn)
          _field(
            controller: _cm,
            suffix: l10n.avatarHeightUnitCm,
            onChanged: (v) => _heightCm = int.tryParse(v.trim()),
          )
        else
          Row(
            children: [
              Expanded(
                child: _field(
                  controller: _ft,
                  suffix: l10n.avatarHeightFeet,
                  onChanged: (_) => _onFtIn(),
                ),
              ),
              const SizedBox(width: WtmSpace.s10),
              Expanded(
                child: _field(
                  controller: _in,
                  suffix: l10n.avatarHeightInches,
                  onChanged: (_) => _onFtIn(),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// A WTM-styled numeric text field (digits only).
  Widget _field({
    required TextEditingController controller,
    String? label,
    String? suffix,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label, style: WtmType.label.copyWith(color: WtmColors.muted)),
          const SizedBox(height: WtmSpace.s8),
        ],
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: onChanged,
          style: WtmType.body,
          cursorColor: WtmColors.gold,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: WtmColors.panel,
            suffixText: suffix,
            suffixStyle: WtmType.micro,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: WtmSpace.s12,
              vertical: WtmSpace.s12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(WtmRadius.button),
              borderSide: const BorderSide(color: WtmColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(WtmRadius.button),
              borderSide: const BorderSide(color: WtmColors.gold),
            ),
          ),
        ),
      ],
    );
  }
}

/// One saved try-on photo — tap selects (gold ring + Active pill), the X deletes,
/// the quality score shows bottom-left.
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.active,
    required this.onTap,
    required this.onDelete,
  });

  final TryonPhoto photo;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final url = photo.signedUrl;
    return Semantics(
      button: true,
      selected: active,
      label: l10n.avatarSelectedBadge,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: _tileW,
            height: _tileH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(WtmRadius.tile),
                  child: url == null
                      ? const AuroraBox()
                      : CachedNetworkImage(
                          imageUrl: url,
                          cacheKey: stableImageCacheKey(url),
                          fit: BoxFit.cover,
                          placeholder: (_, _) => const AuroraBox(),
                          errorWidget: (_, _, _) => const AuroraBox(),
                        ),
                ),
                if (active)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(WtmRadius.tile),
                      border: Border.all(color: WtmColors.gold, width: 2),
                    ),
                  ),
                if (photo.qualityScore != null)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: _MiniBadge(
                      l10n.avatarQualityBadge(photo.qualityScore!),
                    ),
                  ),
                if (active)
                  const Positioned(
                    top: 6,
                    right: 6,
                    child: WtmIcon(
                      WtmGlyph.check,
                      size: 16,
                      color: WtmColors.gold,
                    ),
                  ),
                Positioned(
                  top: 2,
                  left: 2,
                  child: GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xCC000000),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    return Semantics(
      button: true,
      label: l10n.avatarGalleryAdd,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: busy ? null : onTap,
          child: Container(
            width: _tileW,
            height: _tileH,
            decoration: BoxDecoration(
              color: WtmColors.panel,
              borderRadius: BorderRadius.circular(WtmRadius.tile),
              border: Border.all(color: WtmColors.line),
            ),
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: WtmColors.gold,
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const WtmIcon(
                          WtmGlyph.camera,
                          size: 20,
                          color: WtmColors.gold,
                        ),
                        const SizedBox(height: WtmSpace.s6),
                        Text(l10n.avatarGalleryAdd, style: WtmType.micro),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bundled procedural-mannequin body option (dress-form figure).
class _MannequinTile extends StatelessWidget {
  const _MannequinTile({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: _tileW,
            height: _tileH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(WtmRadius.tile),
                  child: const AuroraBox(
                    child: Center(
                      child: SizedBox(
                        width: 64,
                        height: 108,
                        child: WtmFigure(WtmFigureKind.form, opacity: 0.85),
                      ),
                    ),
                  ),
                ),
                if (active)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(WtmRadius.tile),
                      border: Border.all(color: WtmColors.gold, width: 2),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _TileCaption(label, active: active),
                ),
                if (active)
                  const Positioned(
                    top: 6,
                    right: 6,
                    child: WtmIcon(
                      WtmGlyph.check,
                      size: 16,
                      color: WtmColors.gold,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One studio model body option.
class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.active,
    required this.onTap,
  });

  final StudioModelPreset model;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = model.imageUrl;
    return Semantics(
      button: true,
      selected: active,
      label: model.name,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: _tileW,
            height: _tileH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(WtmRadius.tile),
                  child: url == null
                      ? const AuroraBox()
                      : CachedNetworkImage(
                          imageUrl: url,
                          cacheKey: stableImageCacheKey(url),
                          fit: BoxFit.cover,
                          placeholder: (_, _) => const AuroraBox(),
                          errorWidget: (_, _, _) => const AuroraBox(),
                        ),
                ),
                if (active)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(WtmRadius.tile),
                      border: Border.all(color: WtmColors.gold, width: 2),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _TileCaption(model.name, active: active),
                ),
                if (active)
                  const Positioned(
                    top: 6,
                    right: 6,
                    child: WtmIcon(
                      WtmGlyph.check,
                      size: 16,
                      color: WtmColors.gold,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder tile shown when no studio models are available yet — honest, never
/// a broken option (§0.4).
class _SoonTile extends StatelessWidget {
  const _SoonTile({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _tileW,
      height: _tileH,
      padding: const EdgeInsets.all(WtmSpace.s10),
      decoration: BoxDecoration(
        color: WtmColors.panel,
        borderRadius: BorderRadius.circular(WtmRadius.tile),
        border: Border.all(color: WtmColors.line),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const WtmIcon(WtmGlyph.sparkle, size: 18, color: WtmColors.muted),
            const SizedBox(height: WtmSpace.s8),
            Text(label, textAlign: TextAlign.center, style: WtmType.micro),
          ],
        ),
      ),
    );
  }
}

/// A gradient-scrim caption pinned to a tile's bottom (model / mannequin name).
class _TileCaption extends StatelessWidget {
  const _TileCaption(this.label, {required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(WtmRadius.tile),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0xB3000000)],
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: WtmType.micro.copyWith(
            color: active ? WtmColors.gold : Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Color(0xCC000000),
        borderRadius: BorderRadius.circular(WtmRadius.chip),
      ),
      child: Text(
        text,
        style: WtmType.micro.copyWith(color: Colors.white, fontSize: 10),
      ),
    );
  }
}
