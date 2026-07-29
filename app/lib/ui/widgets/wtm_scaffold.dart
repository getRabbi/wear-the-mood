import 'package:flutter/material.dart';

import '../../theme/wtm_colors.dart';

/// The WTM noir backdrop (UI_IMPLEMENTATION.md §4) — an **opaque** base fill,
/// the board's frame gradient (bg2 → bg) and, when [aurora] is on, the soft
/// violet top glow from the phone frame, painted behind [child].
///
/// Opacity is load-bearing, not cosmetic. While a route transition runs,
/// Flutter keeps painting the route *underneath* the incoming one
/// (`TransitionRoute` flips its overlay entry to `opaque = false` for the
/// duration of the animation). A page that paints no background of its own
/// therefore lets the outgoing page show straight through it for the whole
/// push — badly on iOS, where `CupertinoPageTransition` adds no fill of its
/// own and slides the outgoing page across at full opacity. Every routed page
/// must paint this backdrop itself rather than borrowing the shell's.
///
/// Stacking it over the shell's copy is free: the base fill and gradient are
/// fully opaque, so the page's backdrop *replaces* what is below it instead of
/// compositing with it — the glow never doubles up or disappears.
class WtmBackdrop extends StatelessWidget {
  const WtmBackdrop({super.key, required this.child, this.aurora = true});

  final Widget child;

  /// Paints the top violet glow (board phone-frame `::before`).
  final bool aurora;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: WtmColors.bg,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: WtmGradients.scaffoldBase),
            ),
          ),
          if (aurora)
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: WtmGradients.scaffoldGlowRadial,
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// WTM page chrome (UI_IMPLEMENTATION.md §4) — noir scaffold over the
/// [WtmBackdrop]. Content, nav, and safe-area handling stay with the caller so
/// screens keep full layout control.
class WtmScaffold extends StatelessWidget {
  const WtmScaffold({
    super.key,
    required this.body,
    this.aurora = true,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.extendBody = false,
    this.resizeToAvoidBottomInset,
  });

  final Widget body;

  /// Paints the top violet glow (board phone-frame `::before`).
  final bool aurora;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool extendBody;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WtmColors.bg,
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      extendBody: extendBody,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: WtmBackdrop(aurora: aurora, child: body),
    );
  }
}
