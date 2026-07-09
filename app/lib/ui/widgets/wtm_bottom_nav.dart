import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/wtm_colors.dart';
import '../../theme/wtm_typography.dart';
import 'the_orb.dart';
import 'wtm_icons.dart';

/// Test hook: the orb's expanding tap-burst ring (visible only mid-burst).
const wtmOrbBurstRingKey = Key('wtm-orb-burst-ring');

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
                child: Transform.translate(
                  offset: const Offset(0, -20),
                  child: _OrbButton(onTap: onOrbTap),
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

/// The nav orb with a premium TAP BURST (mobile QA #6): a quick breathe-scale,
/// a glow bloom, and an expanding halo ring — one short controller, fired on
/// tap while navigation proceeds INSTANTLY (the burst plays under the opening
/// sheet). Reduced motion skips the burst entirely; the tap still navigates.
class _OrbButton extends StatefulWidget {
  const _OrbButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_OrbButton> createState() => _OrbButtonState();
}

class _OrbButtonState extends State<_OrbButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (MediaQuery.of(context).disableAnimations) {
      widget.onTap(); // reduced motion: no burst, navigate instantly
      return;
    }
    // Light tick — the app's existing nav-tap haptic pattern.
    HapticFeedback.lightImpact();
    _burst.forward(from: 0);
    // Give the bloom a 140ms head start so it's actually SEEN before the
    // Upload Hub sheet + scrim slide over the nav (mobile QA #4) — an
    // imperceptible delay, then navigation proceeds while the burst finishes.
    Future<void>.delayed(const Duration(milliseconds: 140), () {
      if (mounted) widget.onTap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _burst,
        builder: (context, orb) {
          final t = _burst.isAnimating ? _burst.value : 0.0;
          // One sine arc drives the whole burst: swell to +8% and back,
          // with the bloom/halo strongest mid-arc.
          final arc = math.sin(t * math.pi);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Expanding halo ring — grows past the orb and fades.
              if (t > 0)
                IgnorePointer(
                  child: Transform.scale(
                    scale: 1 + 1.1 * t,
                    child: Opacity(
                      opacity: (1 - t).clamp(0.0, 1.0),
                      child: Container(
                        key: wtmOrbBurstRingKey,
                        width: TheOrb.navSize + 10,
                        height: TheOrb.navSize + 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: WtmColors.orbRing,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Glow bloom — an extra violet aura strongest mid-burst.
              if (t > 0)
                IgnorePointer(
                  child: Opacity(
                    opacity: 0.55 * arc,
                    child: Container(
                      width: TheOrb.navSize,
                      height: TheOrb.navSize,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: WtmColors.orbGlowInnerPeak,
                            blurRadius: 42,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Transform.scale(scale: 1 + 0.08 * arc, child: orb),
            ],
          );
        },
        child: const TheOrb(),
      ),
    );
  }
}
