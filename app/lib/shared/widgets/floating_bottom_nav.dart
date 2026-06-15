import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';

/// Visual height of the floating bar (excluding the raised center button and the
/// device safe-area). The shell reserves this much bottom space so tab content
/// never hides behind the bar.
const double kFloatingNavHeight = 72;

/// Bottom space a scrollable should reserve so its content / sticky buttons /
/// empty states never hide behind the floating nav: bar height + device safe
/// area + a comfortable gap (spec). Use as a ListView/GridView bottom padding,
/// or for a sticky bottom bar's bottom inset.
double bottomNavClearance(BuildContext context) =>
    kFloatingNavHeight + MediaQuery.of(context).viewPadding.bottom + AppSpace.lg;

/// A single side-tab definition for [FloatingBottomNav].
class NavTab {
  const NavTab({required this.icon, required this.activeIcon, required this.label});
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Modern rounded floating bottom navigation (CLAUDE.md §4 + redesign spec).
/// Five slots with the **Try-On** center tab raised into a glowing gradient
/// button — the app's core action. Active side-tabs get an animated pill
/// highlight; every tap fires selection haptics. Sized with `Expanded` slots so
/// it never overflows on small (≤360dp) screens.
class FloatingBottomNav extends StatelessWidget {
  const FloatingBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.leftTabs,
    required this.rightTabs,
    required this.centerLabel,
    this.centerIndex = 2,
  });

  /// The two tabs left of center (indices 0 and 1).
  final List<NavTab> leftTabs;

  /// The two tabs right of center (indices 3 and 4).
  final List<NavTab> rightTabs;
  final String centerLabel;
  final int centerIndex;
  final int currentIndex;
  final ValueChanged<int> onTap;

  void _select(int index) {
    HapticFeedback.selectionClick();
    onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.md,
        0,
        AppSpace.md,
        bottomInset > 0 ? bottomInset : AppSpace.md,
      ),
      child: Container(
        height: kFloatingNavHeight,
        decoration: BoxDecoration(
          // Dark glass bar (spec): elevated plum surface + hairline highlight.
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xF22B1C44), Color(0xF21C1130)],
          ),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 30,
              offset: Offset(0, 12),
            ),
          ],
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            _SideTab(
              tab: leftTabs[0],
              selected: currentIndex == 0,
              onTap: () => _select(0),
            ),
            _SideTab(
              tab: leftTabs[1],
              selected: currentIndex == 1,
              onTap: () => _select(1),
            ),
            _CenterTab(
              label: centerLabel,
              selected: currentIndex == centerIndex,
              onTap: () => _select(centerIndex),
            ),
            _SideTab(
              tab: rightTabs[0],
              selected: currentIndex == 3,
              onTap: () => _select(3),
            ),
            _SideTab(
              tab: rightTabs[1],
              selected: currentIndex == 4,
              onTap: () => _select(4),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideTab extends StatelessWidget {
  const _SideTab({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final NavTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.graphite;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: tab.label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: AppMotion.base,
                curve: AppMotion.spring,
                padding: EdgeInsets.symmetric(
                  horizontal: selected ? 16 : 6,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: selected ? AppColors.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Icon(
                  selected ? tab.activeIcon : tab.icon,
                  color: color,
                  size: 23,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterTab extends StatelessWidget {
  const _CenterTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.translate(
                offset: const Offset(0, -12),
                child: AnimatedScale(
                  scale: selected ? 1.08 : 1,
                  duration: AppMotion.base,
                  curve: AppMotion.spring,
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: AppGradients.brand,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x547B2FF7),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -8),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.accent : AppColors.violet,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
