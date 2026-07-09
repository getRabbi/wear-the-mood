import 'package:flutter/material.dart';

import '../../theme/wtm_colors.dart';

/// WTM page chrome (UI_IMPLEMENTATION.md §4) — noir scaffold with the board's
/// frame gradient (bg2 → bg) and, when [aurora] is on, the soft violet top
/// glow from the phone frame. Content, nav, and safe-area handling stay with
/// the caller so screens keep full layout control.
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
      body: Stack(
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
          body,
        ],
      ),
    );
  }
}
