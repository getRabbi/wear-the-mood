import 'package:flutter/material.dart';

import '../../theme/wtm_colors.dart';
import '../../theme/wtm_typography.dart';
import 'the_orb.dart';
import 'wtm_icons.dart';

/// One of the four labeled nav destinations (§2 locked order:
/// Home · Social · [orb] · Inbox · Profile).
class WtmNavItem {
  const WtmNavItem({required this.glyph, required this.label});

  final WtmGlyph glyph;
  final String label;
}

/// Persistent bottom nav (board `.navbar`, §4 `WtmBottomNav`) — translucent
/// noir wash over content (host the scaffold with `extendBody: true`), gold
/// active state, and the breathing orb floating 20px above the bar as the
/// center "+" (opens the Upload Hub sheet).
class WtmBottomNav extends StatelessWidget {
  const WtmBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.onOrbTap,
    this.orbSemanticLabel,
  });

  /// Exactly four items — two each side of the orb.
  final List<WtmNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onOrbTap;
  final String? orbSemanticLabel;

  @override
  Widget build(BuildContext context) {
    assert(items.length == 4, 'WtmBottomNav takes exactly 4 items (§2)');
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: WtmGradients.navFill,
        border: Border(top: BorderSide(color: WtmColors.lineSoft)),
      ),
      child: Padding(
        // Board: 9px top, 14px sides, 15px bottom + device inset.
        padding: EdgeInsets.fromLTRB(14, 9, 14, 15 + bottomInset),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _item(0),
            _item(1),
            // The orb rides 20px above the bar (board `.navbar .orb`).
            Semantics(
              button: true,
              label: orbSemanticLabel,
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onOrbTap,
                  child: Transform.translate(
                    offset: const Offset(0, -20),
                    child: const TheOrb(),
                  ),
                ),
              ),
            ),
            _item(2),
            _item(3),
          ],
        ),
      ),
    );
  }

  Widget _item(int index) {
    final item = items[index];
    final on = index == currentIndex;
    final color = on ? WtmColors.gold : WtmColors.faint;
    return Semantics(
      button: true,
      selected: on,
      label: item.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(index),
          child: SizedBox(
            width: 46, // .nitem
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                WtmIcon(item.glyph, color: color),
                const SizedBox(height: 4),
                Text(
                  item.label.toUpperCase(),
                  maxLines: 1,
                  style: WtmType.micro.copyWith(
                    fontSize: 8, // .nitem span
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.96, // .12em × 8
                    color: color,
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
