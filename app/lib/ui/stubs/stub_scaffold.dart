import 'package:flutter/material.dart';

import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

// The shared chrome (WtmPage) and dialog helpers now live in the kit — stubs
// re-export them so stub files keep one import.
export '../widgets/wtm_dialogs.dart';
export '../widgets/wtm_page.dart' show wtmNavClearance, wtmPageBack;

/// P1 STUB CHROME (UI_IMPLEMENTATION.md §5) — [WtmPage] plus the honest phase
/// banner. Every stub is a real, navigable destination in the shell; each is
/// replaced by its full screen in the phase named on its banner. Stub copy is
/// intentionally not localized — it ships to no user and is deleted phase by
/// phase.
class WtmStubScreen extends StatelessWidget {
  const WtmStubScreen({
    super.key,
    required this.title,
    this.eyebrow,
    this.phase,
    this.showBack = true,
    this.trailing,
    this.children = const [],
    this.fullBleed = false,
  });

  final String title;
  final String? eyebrow;

  /// Which phase replaces this stub ("P4") — renders the banner when set.
  final String? phase;
  final bool showBack;
  final Widget? trailing;
  final List<Widget> children;
  final bool fullBleed;

  @override
  Widget build(BuildContext context) {
    return WtmPage(
      title: title,
      eyebrow: eyebrow,
      showBack: showBack,
      trailing: trailing,
      fullBleed: fullBleed,
      children: [
        if (phase != null) ...[
          WtmStubBanner(phase: phase!),
          const SizedBox(height: WtmSpace.s14),
        ],
        ...children,
      ],
    );
  }
}

/// Back that can never dead-end (kit [wtmPageBack], stub-era name).
void wtmStubBack(BuildContext context) => wtmPageBack(context);

/// Kit [wtmSnack], stub-era name.
void wtmStubSnack(BuildContext context, String message) =>
    wtmSnack(context, message);

/// The honest little marker on every stub.
class WtmStubBanner extends StatelessWidget {
  const WtmStubBanner({super.key, required this.phase});

  final String phase;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(WtmRadius.chip),
          border: Border.all(color: WtmColors.lineSoft),
        ),
        child: Text(
          'P1 STUB · REAL SCREEN LANDS IN $phase',
          style: WtmType.micro.copyWith(letterSpacing: 1.2),
        ),
      ),
    );
  }
}

/// Serif-initials avatar (board `.avatar`).
class WtmStubAvatar extends StatelessWidget {
  const WtmStubAvatar(this.initials, {super.key, this.size = 34});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        border: Border.fromBorderSide(
          BorderSide(color: WtmColors.pillBorder),
        ),
        gradient: RadialGradient(
          center: Alignment(-0.4, -0.5),
          radius: 1.2,
          colors: [Color(0x4DBE78FF), Color(0x8C3C236E), Color(0xFF150D28)],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: WtmType.h2.copyWith(fontSize: size * 0.38, color: WtmColors.gold),
      ),
    );
  }
}

// WtmDashedBox now lives in the kit (ui/widgets/wtm_dashed_box.dart) — promoted
// for the real Outfit Maker (P5); stubs get it via the widgets barrel.
