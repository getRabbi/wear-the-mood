import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/legal/legal_links.dart';
import '../../core/network/api_exception.dart';
import '../../core/privacy/ai_consent_controller.dart';
import '../../core/privacy/ai_consent_repository.dart';
import '../../core/privacy/ai_disclosure_sheet.dart';
import '../../data/repositories/account_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Settings → Privacy.
///
/// Two jobs. For users: one place to see whether AI features may use their
/// photo, read the disclosure again, and take the permission back. For App
/// Review: a route to the disclosure that works even when the review account has
/// already consented — a reviewer who cannot re-open the sheet cannot verify it
/// exists, which is how a fix gets rejected twice.
class WtmPrivacyScreen extends ConsumerStatefulWidget {
  const WtmPrivacyScreen({super.key});

  @override
  ConsumerState<WtmPrivacyScreen> createState() => _WtmPrivacyScreenState();
}

class _WtmPrivacyScreenState extends ConsumerState<WtmPrivacyScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The cached value can be a session old; this screen is where it must be
    // exact, because it is the screen that claims to state the current status.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(aiConsentProvider.notifier).refresh();
    });
  }

  /// Re-open the disclosure. Allowing from here records consent exactly as the
  /// just-in-time sheet does; declining leaves the current state untouched
  /// rather than silently withdrawing it — the user asked to READ it, and
  /// closing something you opened to read is not a withdrawal.
  Future<void> _review() async {
    final l10n = AppLocalizations.of(context);
    final choice = await showAiDisclosureSheet(context);
    if (choice != AiDisclosureChoice.allow || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(aiConsentProvider.notifier).grant();
      if (mounted) wtmSnack(context, l10n.privacyAiAllowed);
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.privacyAiError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(aiConsentProvider.notifier).revoke();
      if (mounted) wtmSnack(context, l10n.privacyAiWithdrawn);
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.privacyAiError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// GDPR export (§10) — moved here from the Settings root so every data right
  /// lives behind one door.
  Future<void> _export() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final data = await ref.read(accountRepositoryProvider).exportData();
      await Clipboard.setData(
        ClipboardData(text: const JsonEncoder.withIndent('  ').convert(data)),
      );
      if (mounted) wtmSnack(context, l10n.wtmSettingsExportDone);
    } on ApiException {
      if (mounted) wtmSnack(context, l10n.wtmSettingsExportError);
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.wtmSettingsExportError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final consent = ref.watch(aiConsentProvider);
    // While loading or after a failed read we show "Not allowed": the honest
    // reading of "we do not currently hold a usable permission", and the same
    // answer the gate would act on.
    final allowed =
        consent.asData?.value.isCurrent ??
        const AiConsentState.unknown().isCurrent;

    return Stack(
      children: [
        WtmPage(
          // Hosted OUTSIDE the shell, so this page supplies its own Scaffold —
          // without it the confirmation snackbars have nowhere to present.
          fullBleed: true,
          title: l10n.privacyTitle,
          eyebrow: l10n.privacyEyebrow,
          children: [
            Container(
              padding: const EdgeInsets.all(WtmSpace.s14),
              decoration: BoxDecoration(
                gradient: WtmGradients.cardFill,
                borderRadius: BorderRadius.circular(WtmRadius.card),
                border: Border.all(color: WtmColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.privacyAiTitle,
                          style: WtmType.labelMedium,
                        ),
                      ),
                      const SizedBox(width: WtmSpace.s8),
                      _StatusChip(allowed: allowed),
                    ],
                  ),
                  const SizedBox(height: WtmSpace.s8),
                  Text(l10n.privacyAiSub, style: WtmType.micro),
                  const SizedBox(height: WtmSpace.s14),
                  GhostButton(
                    label: l10n.privacyAiReview,
                    onPressed: _busy ? null : _review,
                  ),
                  if (allowed) ...[
                    const SizedBox(height: 9),
                    // Ordinary permission management, not a destructive act —
                    // so no danger red. Nothing is deleted by pressing it.
                    GhostButton(
                      label: l10n.privacyAiWithdraw,
                      onPressed: _busy ? null : _withdraw,
                    ),
                  ],
                  const SizedBox(height: WtmSpace.s12),
                  Text(l10n.privacyAiNote, style: WtmType.micro),
                ],
              ),
            ),
            const SizedBox(height: WtmSpace.s12),
            Text(l10n.privacyAiLocalNote, style: WtmType.micro),
            const SizedBox(height: WtmSpace.s18),
            WtmRow(
              glyph: WtmGlyph.shield,
              title: l10n.wtmSettingsPrivacyPolicy,
              onTap: () => launchUrl(
                Uri.parse(LegalLinks.privacy),
                mode: LaunchMode.externalApplication,
              ),
            ),
            const SizedBox(height: 9),
            WtmRow(
              glyph: WtmGlyph.bookmark,
              title: l10n.wtmSettingsExport,
              subtitle: l10n.wtmSettingsExportSub,
              onTap: _busy ? null : _export,
            ),
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

/// Allowed / Not allowed. Carries a semantic label so the status is announced
/// with the setting it belongs to rather than as a loose word.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.allowed});

  final bool allowed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = allowed
        ? l10n.privacyAiStatusAllowed
        : l10n.privacyAiStatusNotAllowed;
    return Semantics(
      label: '${l10n.privacyAiTitle}: $label',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(WtmRadius.chip),
            border: Border.all(
              color: allowed ? WtmColors.gold : WtmColors.pillBorder,
            ),
            color: WtmColors.pillBg,
          ),
          child: Text(
            label.toUpperCase(),
            style: WtmType.micro.copyWith(
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
              color: allowed ? WtmColors.gold : WtmColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
