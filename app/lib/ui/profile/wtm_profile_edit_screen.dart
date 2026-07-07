import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/profile_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_profile_photo.dart';

/// WTM Edit Profile (board §3.1, P7) — the real profile form on
/// [ProfileRepository.updateProfile]: display name, bio, style tags (seed the
/// Style DNA), and the public toggle. Save patches the server and refreshes the
/// profile everywhere.
class WtmProfileEditScreen extends ConsumerStatefulWidget {
  const WtmProfileEditScreen({super.key});

  @override
  ConsumerState<WtmProfileEditScreen> createState() =>
      _WtmProfileEditScreenState();
}

class _WtmProfileEditScreenState extends ConsumerState<WtmProfileEditScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _tags = TextEditingController();
  bool _primed = false;
  bool _isPublic = true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _prime(Profile p) {
    if (_primed) return;
    _primed = true;
    _name.text = p.displayName ?? '';
    _bio.text = p.bio ?? '';
    _tags.text = p.styleTags.join(', ');
    _isPublic = p.isPublic;
  }

  List<String> _parseTags() => [
        for (final raw in _tags.text.split(','))
          if (raw.trim().replaceFirst('#', '').trim().isNotEmpty)
            raw.trim().replaceFirst('#', '').trim(),
      ];

  Future<void> _save() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            displayName: _name.text.trim(),
            bio: _bio.text.trim(),
            styleTags: _parseTags(),
            isPublic: _isPublic,
          );
      ref.invalidate(profileProvider);
      if (mounted) {
        wtmSnack(context, l10n.wtmEditSaved);
        wtmPageBack(context);
      }
    } on ApiException {
      if (mounted) wtmSnack(context, l10n.wtmEditError);
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.wtmEditError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _field(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: WtmType.body.copyWith(color: WtmColors.faint),
        filled: true,
        fillColor: WtmColors.iconBtnBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WtmRadius.button),
          borderSide: const BorderSide(color: WtmColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WtmRadius.button),
          borderSide: const BorderSide(color: WtmColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WtmRadius.button),
          borderSide: const BorderSide(color: WtmColors.chipOnBorder),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profileAsync = ref.watch(profileProvider);

    return WtmPage(
      title: l10n.wtmEditTitle,
      eyebrow: l10n.wtmEditEyebrow,
      children: profileAsync.when<List<Widget>>(
        skipLoadingOnReload: true,
        loading: () => const [
          LoadingShimmer(width: double.infinity, height: 52),
          SizedBox(height: WtmSpace.s10),
          LoadingShimmer(width: double.infinity, height: 88),
        ],
        error: (_, _) => [
          WtmErrorState(
            title: l10n.wtmProfileSignedOutTitle,
            message: l10n.wtmProfileSignedOutMessage,
            retryLabel: l10n.commonRetry,
            onRetry: () => ref.invalidate(profileProvider),
          ),
        ],
        data: (profile) {
          _prime(profile);
          final photoUrl = profile.profilePictureDisplayUrl;
          return [
            // Display picture — add/change via the shipped upload flow.
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: WtmGradients.cardFill,
                borderRadius: BorderRadius.circular(WtmRadius.card),
                border: Border.all(color: WtmColors.line),
              ),
              child: Row(
                children: [
                  WtmProfilePhotoAvatar(url: photoUrl, size: 52),
                  const SizedBox(width: WtmSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.wtmProfilePhotoTitle,
                            style: WtmType.labelMedium),
                        Text(l10n.profilePictureHint,
                            style: WtmType.micro,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: WtmSpace.s8),
                  GoldPill(
                    label: l10n.wtmProfilePhotoChange,
                    onTap: _busy
                        ? null
                        : () => showWtmProfilePhotoSheet(
                              context,
                              ref,
                              hasPicture:
                                  photoUrl != null && photoUrl.isNotEmpty,
                              viewUrl: photoUrl,
                            ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: WtmSpace.s10),
            TextField(
              controller: _name,
              style: WtmType.body,
              cursorColor: WtmColors.gold,
              textCapitalization: TextCapitalization.words,
              decoration: _field(l10n.wtmEditNameHint),
            ),
            const SizedBox(height: WtmSpace.s10),
            TextField(
              controller: _bio,
              style: WtmType.body,
              cursorColor: WtmColors.gold,
              maxLines: 3,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              decoration: _field(l10n.wtmEditBioHint),
            ),
            const SizedBox(height: WtmSpace.s10),
            TextField(
              controller: _tags,
              style: WtmType.body,
              cursorColor: WtmColors.gold,
              decoration: _field(l10n.wtmEditTagsHint),
            ),
            const SizedBox(height: WtmSpace.s6),
            Text(l10n.wtmEditTagsNote, style: WtmType.micro),
            const SizedBox(height: WtmSpace.s12),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: WtmGradients.cardFill,
                borderRadius: BorderRadius.circular(WtmRadius.card),
                border: Border.all(color: WtmColors.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.wtmEditPublicTitle,
                            style: WtmType.labelMedium),
                        Text(l10n.wtmEditPublicSub, style: WtmType.micro),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isPublic,
                    activeThumbColor: WtmColors.gold,
                    onChanged:
                        _busy ? null : (v) => setState(() => _isPublic = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: WtmSpace.s16),
            GradientCta(
              label: l10n.wtmEditSave,
              icon: const WtmIcon(WtmGlyph.check,
                  size: 15, color: WtmColors.ctaText),
              onPressed: _busy ? null : _save,
            ),
          ];
        },
      ),
    );
  }
}
