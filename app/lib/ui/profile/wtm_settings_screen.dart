import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/legal/legal_links.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../data/repositories/account_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// WTM Settings (board 12 + §3.1 rows, P7) — on the shipped account lifecycle.
/// The compliance rows are real: data export (§10), in-app **Delete Account**
/// (double-confirmed → server delete + sign-out, the App Store requirement),
/// Sign Out, Subscription → paywall, and the legal links.
class WtmSettingsScreen extends ConsumerStatefulWidget {
  const WtmSettingsScreen({super.key});

  @override
  ConsumerState<WtmSettingsScreen> createState() => _WtmSettingsScreenState();
}

class _WtmSettingsScreenState extends ConsumerState<WtmSettingsScreen> {
  bool _busy = false;

  void _snack(String message) {
    if (!mounted) return;
    wtmSnack(context, message);
  }

  /// GDPR export (§10) — pulls all of the user's data and copies it as JSON,
  /// mirroring the shipped profile screen.
  Future<void> _export() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final data = await ref.read(accountRepositoryProvider).exportData();
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      await Clipboard.setData(ClipboardData(text: pretty));
      _snack(l10n.wtmSettingsExportDone);
    } on ApiException {
      _snack(l10n.wtmSettingsExportError);
    } catch (_) {
      _snack(l10n.wtmSettingsExportError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// In-app account deletion (§10) — double-confirmed, irreversible. Deletes
  /// server-side, then clears the local session and returns to a clean state.
  Future<void> _delete() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final first = await wtmConfirmDialog(
      context,
      title: l10n.wtmSettingsDelete1Title,
      message: l10n.wtmSettingsDelete1Body,
      confirmLabel: l10n.wtmSettingsDelete1Confirm,
      danger: true,
    );
    if (!first || !mounted) return;
    final second = await wtmConfirmDialog(
      context,
      title: l10n.wtmSettingsDelete2Title,
      message: l10n.wtmSettingsDelete2Body,
      confirmLabel: l10n.wtmSettingsDelete2Confirm,
      danger: true,
    );
    if (!second || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(accountRepositoryProvider).deleteAccount();
      await ref.read(authRepositoryProvider).signOut();
      _snack(l10n.wtmSettingsDeleteDone);
      // Land on the WTM auth gate — never the legacy shell (URGENT auth fix).
      if (mounted) context.go(AppRoute.wtmAuth);
    } on ApiException {
      _snack(l10n.wtmSettingsDeleteError);
      if (mounted) setState(() => _busy = false);
    } catch (_) {
      _snack(l10n.wtmSettingsDeleteError);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await wtmConfirmDialog(
      context,
      title: l10n.wtmSettingsSignOutTitle,
      message: l10n.wtmSettingsSignOutBody,
      confirmLabel: l10n.wtmSettingsSignOut,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
      // Land on the WTM auth gate — never the legacy shell (URGENT auth fix).
      if (mounted) context.go(AppRoute.wtmAuth);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Future<void> info(String title) =>
        showWtmSheet(context, title: title, subtitle: l10n.wtmSettingsMore);

    return Stack(
      children: [
        WtmPage(
          title: l10n.wtmSettingsTitle,
          eyebrow: l10n.wtmSettingsEyebrow,
          children: [
            WtmRow(
              glyph: WtmGlyph.user,
              title: l10n.wtmSettingsAccount,
              subtitle: l10n.wtmSettingsAccountSub,
              onTap: () => context.push(AppRoute.wtmProfileEdit),
            ),
            const SizedBox(height: 9),
            WtmRow(
              glyph: WtmGlyph.sliders,
              title: l10n.wtmSettingsPrefs,
              subtitle: l10n.wtmSettingsPrefsSub,
              onTap: () => info(l10n.wtmSettingsPrefs),
            ),
            const SizedBox(height: 9),
            WtmRow(
              glyph: WtmGlyph.bell,
              title: l10n.wtmSettingsNotifs,
              subtitle: l10n.wtmSettingsNotifsSub,
              onTap: () => info(l10n.wtmSettingsNotifs),
            ),
            const SizedBox(height: 9),
            WtmRow(
              glyph: WtmGlyph.sparkle,
              title: l10n.wtmSettingsSubscription,
              subtitle: l10n.wtmSettingsSubscriptionSub,
              onTap: () => context.push(AppRoute.wtmPaywall),
            ),
            const SizedBox(height: 9),
            WtmRow(
              glyph: WtmGlyph.shield,
              title: l10n.wtmSettingsPrivacy,
              subtitle: l10n.wtmSettingsPrivacySub,
              onTap: _busy ? null : _export,
            ),
            const SizedBox(height: 9),
            WtmRow(
              glyph: WtmGlyph.bookmark,
              title: l10n.wtmSettingsLegal,
              subtitle: l10n.wtmSettingsLegalSub,
              onTap: () => showWtmSheet(
                context,
                title: l10n.wtmSettingsLegal,
                children: [
                  WtmRow(
                    glyph: WtmGlyph.shield,
                    title: l10n.wtmSettingsPrivacyPolicy,
                    onTap: () => launchUrl(Uri.parse(LegalLinks.privacy),
                        mode: LaunchMode.externalApplication),
                  ),
                  const SizedBox(height: 9),
                  WtmRow(
                    glyph: WtmGlyph.bookmark,
                    title: l10n.wtmSettingsTerms,
                    onTap: () => launchUrl(Uri.parse(LegalLinks.terms),
                        mode: LaunchMode.externalApplication),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            WtmRow(
              glyph: WtmGlyph.help,
              title: l10n.wtmSettingsHelp,
              subtitle: l10n.wtmSettingsHelpSub,
              onTap: () => info(l10n.wtmSettingsHelp),
            ),
            const SizedBox(height: 9),
            WtmRow(
              glyph: WtmGlyph.erase,
              title: l10n.wtmSettingsDelete,
              subtitle: l10n.wtmSettingsDeleteSub,
              titleColor: WtmColors.danger,
              iconColor: WtmColors.danger,
              onTap: _busy ? null : _delete,
            ),
            const SizedBox(height: 9),
            WtmRow(
              glyph: WtmGlyph.back,
              title: l10n.wtmSettingsSignOut,
              onTap: _busy ? null : _signOut,
            ),
            const SizedBox(height: WtmSpace.s18),
            EyebrowLabel(l10n.wtmSettingsBodyPhoto),
            const SizedBox(height: WtmSpace.s10),
            Container(
              padding: const EdgeInsets.all(WtmSpace.s12),
              decoration: BoxDecoration(
                gradient: WtmGradients.cardFill,
                borderRadius: BorderRadius.circular(WtmRadius.card),
                border: Border.all(color: WtmColors.line),
              ),
              child: Row(
                children: [
                  const AuroraBox(
                    width: 50,
                    height: 64,
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                  const SizedBox(width: WtmSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.wtmSettingsBodyPhotoTitle,
                            style: WtmType.labelMedium),
                        const SizedBox(height: 3),
                        Text(l10n.wtmSettingsBodyPhotoSub,
                            style: WtmType.micro),
                      ],
                    ),
                  ),
                  GoldPill(
                    label: l10n.wtmSettingsUpdate,
                    onTap: () => context.push(AppRoute.wtmBodyPhoto),
                  ),
                ],
              ),
            ),
            const SizedBox(height: WtmSpace.s16),
            Center(child: Text(l10n.wtmSettingsVersion, style: WtmType.micro)),
          ],
        ),
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66000000),
              child: Center(
                child: CircularProgressIndicator(color: WtmColors.gold),
              ),
            ),
          ),
      ],
    );
  }
}
