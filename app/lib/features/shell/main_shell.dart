import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/widgets/floating_bottom_nav.dart';
import '../community/community_screen.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../tryon/tryon_screen.dart';
import '../wardrobe/wardrobe_screen.dart';
import 'shell_providers.dart';

/// The signed-in app shell: a modern floating 5-tab navigation across the core
/// daily-use surfaces (CLAUDE.md §1) with **Try-On** as the raised center action
/// — the app's hook. Full-screen flows (auth, paywall, item detail) push over
/// this shell via the router. Tabs keep their state via an [IndexedStack], and
/// the body reserves bottom space so content never hides behind the floating bar.
class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  // Order MUST match the nav slots: Home, Closet, Try-On (center), Community,
  // Profile. WardrobeScreen powers the "Closet" tab (renamed in the UI only).
  static const _tabs = [
    HomeScreen(),
    WardrobeScreen(),
    TryOnScreen(),
    CommunityScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final index = ref.watch(shellTabProvider);

    void onTap(int i) => ref.read(shellTabProvider.notifier).select(i);

    // Each tab screen reserves bottom space for the floating bar itself via
    // `bottomNavClearance(...)` on its scrollables — see the per-screen padding.
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(index: index, children: _tabs),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingBottomNav(
              currentIndex: index,
              onTap: onTap,
              centerLabel: l10n.navTryOn,
              // Invite the core action with a gentle glow pulse while on Home.
              centerIdlePulse: index == 0,
              leftTabs: [
                NavTab(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: l10n.navHome,
                ),
                NavTab(
                  icon: Icons.checkroom_outlined,
                  activeIcon: Icons.checkroom_rounded,
                  label: l10n.navCloset,
                ),
              ],
              rightTabs: [
                NavTab(
                  icon: Icons.groups_outlined,
                  activeIcon: Icons.groups_rounded,
                  label: l10n.navSocial,
                ),
                NavTab(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: l10n.profileTitle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
