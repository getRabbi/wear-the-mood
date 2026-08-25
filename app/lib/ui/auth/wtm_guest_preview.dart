import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/guest_session.dart';
import '../../core/auth/protected_action.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_guest_conversion_sheet.dart';

/// Renders [child] for an authenticated user and a feature preview for a guest.
///
/// Used at the ROUTE BUILDER for the two surfaces that deserve an explanation
/// rather than a bounce — the Closet and the try-on entry. A guest who taps
/// "Closet" should learn what a closet is for; being silently returned to Home
/// teaches them nothing and reads like a bug.
///
/// The real screen is never MOUNTED for a guest, so none of its providers
/// initialise and no request is made. Constructing the widget object costs
/// nothing; only insertion into the tree runs anything.
class GuestPreviewGate extends ConsumerWidget {
  const GuestPreviewGate({
    super.key,
    required this.action,
    required this.preview,
    required this.child,
  });

  final ProtectedAction action;
  final Widget preview;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(isGuestSessionProvider) ? preview : child;
  }
}

/// Shared chrome for a guest feature preview: the orb, a headline, a body, an
/// optional bullet list, and the one CTA.
class _GuestPreviewScaffold extends ConsumerWidget {
  const _GuestPreviewScaffold({
    required this.action,
    required this.title,
    required this.body,
    this.bullets = const [],
    this.footnote,
  });

  final ProtectedAction action;
  final String title;
  final String body;
  final List<String> bullets;
  final String? footnote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return WtmScaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuroraBox(
            borderRadius: BorderRadius.zero,
            border: false,
            vignette: true,
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                WtmSpace.screenH,
                WtmSpace.s22,
                WtmSpace.screenH,
                // Clears the translucent bottom nav the shell draws over this.
                104,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: TheOrb(size: 64)),
                      const SizedBox(height: WtmSpace.s18),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: WtmType.h1.copyWith(fontSize: 23),
                      ),
                      const SizedBox(height: WtmSpace.s10),
                      Text(
                        body,
                        textAlign: TextAlign.center,
                        style: WtmType.sub,
                      ),
                      if (bullets.isNotEmpty) ...[
                        const SizedBox(height: WtmSpace.s18),
                        for (final bullet in bullets) ...[
                          _PreviewBullet(text: bullet),
                          const SizedBox(height: WtmSpace.s10),
                        ],
                      ],
                      if (footnote != null) ...[
                        const SizedBox(height: WtmSpace.s8),
                        Text(
                          footnote!,
                          textAlign: TextAlign.center,
                          style: WtmType.micro,
                        ),
                      ],
                      const SizedBox(height: WtmSpace.s18),
                      GradientCta(
                        label: l10n.wtmWelcomeCreate,
                        onPressed: () => showGuestConversionSheet(
                          context,
                          ref,
                          action: action,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewBullet extends StatelessWidget {
  const _PreviewBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 3),
          child: WtmIcon(WtmGlyph.sparkle, size: 15, color: WtmColors.gold),
        ),
        const SizedBox(width: WtmSpace.s10),
        Expanded(child: Text(text, style: WtmType.body)),
      ],
    );
  }
}

/// What the Closet is for, shown to a guest instead of an empty grid.
class WtmGuestClosetPreview extends StatelessWidget {
  const WtmGuestClosetPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _GuestPreviewScaffold(
      action: ProtectedAction.closet,
      title: l10n.wtmGuestClosetPreviewTitle,
      body: l10n.wtmGuestClosetBody,
      bullets: [
        l10n.wtmGuestClosetPreviewOne,
        l10n.wtmGuestClosetPreviewTwo,
        l10n.wtmGuestClosetPreviewThree,
      ],
    );
  }
}

/// How try-on works, in words.
///
/// There is deliberately **no sample image**. Every result this app produces is
/// generated from the user's own photograph, so any picture shown here would
/// either be someone else's body presented as an example of theirs, or a
/// fabricated render — and the footnote says so plainly rather than leaving a
/// gap the reader has to explain to themselves.
class WtmGuestTryOnPreview extends StatelessWidget {
  const WtmGuestTryOnPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _GuestPreviewScaffold(
      action: ProtectedAction.tryOn,
      title: l10n.wtmGuestTryOnPreviewTitle,
      body: l10n.wtmGuestTryOnPreviewBody,
      footnote: l10n.wtmGuestTryOnPreviewNote,
    );
  }
}

/// The guest Profile tab: an honest statement of what guest mode stores
/// (nothing on an account) plus the one CTA. Not a fake profile.
class WtmGuestProfilePreview extends StatelessWidget {
  const WtmGuestProfilePreview({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _GuestPreviewScaffold(
      action: ProtectedAction.profile,
      title: l10n.wtmGuestProfileTitle,
      body: l10n.wtmGuestProfileBody,
    );
  }
}

/// A non-blocking benefit card for the guest Home.
///
/// It sits in the page like any other module and scrolls away with it. It is
/// never a timed popup, never an interstitial, and never reappears on a
/// schedule — those are the patterns 5.1.1(v) is reacting to, and adding one
/// here would be answering a rejection with a smaller version of the same
/// behaviour.
class WtmGuestBenefitCard extends ConsumerWidget {
  const WtmGuestBenefitCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isGuestSessionProvider)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    // No horizontal padding of its own: this sits inside Home's already-padded
    // list, and adding more here would inset it from every other module. The
    // top margin is the card's, so nothing is left behind when it is absent.
    return Padding(
      padding: const EdgeInsets.only(top: WtmSpace.s18),
      child: Container(
        padding: const EdgeInsets.all(WtmSpace.s14),
        decoration: BoxDecoration(
          gradient: WtmGradients.assistFill,
          borderRadius: BorderRadius.circular(WtmRadius.card),
          border: Border.all(color: WtmColors.assistBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const TheOrb(size: TheOrb.miniSize),
                const SizedBox(width: WtmSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.wtmGuestBenefitTitle,
                        style: WtmType.h2.copyWith(fontSize: 17),
                      ),
                      const SizedBox(height: WtmSpace.s4),
                      Text(
                        l10n.wtmGuestBenefitBody,
                        style: WtmType.body.copyWith(
                          fontSize: 12,
                          color: WtmColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: WtmSpace.s12),
            GradientCta(
              label: l10n.wtmWelcomeCreate,
              onPressed: () => showGuestConversionSheet(
                context,
                ref,
                action: ProtectedAction.profile,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
