import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../widgets/widgets.dart';
import 'upload_hub_sheet.dart';

/// WTM Atelier nav shell (§2 LOCKED) — persistent bottom nav
/// `Home · Social · [ORB] · Inbox · Profile` over an indexed-stack of branch
/// navigators. The orb opens the Upload Hub sheet; it is never a tab.
class WtmShell extends StatelessWidget {
  const WtmShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WtmScaffold(
      // Content scrolls under the translucent nav wash (board .navbar).
      extendBody: true,
      body: shell,
      bottomNavigationBar: WtmBottomNav(
        items: [
          WtmNavItem(glyph: WtmGlyph.home, label: l10n.wtmNavHome),
          WtmNavItem(glyph: WtmGlyph.users, label: l10n.wtmNavSocial),
          WtmNavItem(glyph: WtmGlyph.inbox, label: l10n.wtmNavInbox),
          WtmNavItem(glyph: WtmGlyph.user, label: l10n.wtmNavProfile),
        ],
        currentIndex: shell.currentIndex,
        onTap: (index) => shell.goBranch(
          index,
          // Re-tapping the active tab resets it to its root (standard).
          initialLocation: index == shell.currentIndex,
        ),
        onOrbTap: () => showUploadHubSheet(context),
        orbSemanticLabel: l10n.wtmNavOrb,
      ),
    );
  }
}
