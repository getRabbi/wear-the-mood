import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/flags/feature_flags.dart';
import '../../core/push/push_messaging.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/widgets.dart';
import 'upload_hub_sheet.dart';

/// WTM Atelier nav shell (§2 LOCKED) — persistent bottom nav
/// `Home · Social · [ORB] · Inbox · Profile` over an indexed-stack of branch
/// navigators. The orb opens the Upload Hub sheet; it is never a tab.
///
/// Also the host for the FOREGROUND push banner. FCM does not draw a system
/// notification while the app is in the foreground, so a push arriving
/// mid-session would otherwise be completely invisible; the shell is the one
/// widget alive for the whole signed-in session, which makes it the right place
/// to show it (§20).
class WtmShell extends ConsumerStatefulWidget {
  const WtmShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<WtmShell> createState() => _WtmShellState();
}

class _WtmShellState extends ConsumerState<WtmShell> {
  @override
  void initState() {
    super.initState();
    foregroundPushes.addListener(_onForegroundPush);
  }

  @override
  void dispose() {
    foregroundPushes.removeListener(_onForegroundPush);
    super.dispose();
  }

  void _onForegroundPush() {
    final push = foregroundPushes.value;
    if (push == null || !mounted) return;
    // Consume it, so a rebuild or a second listener can't show the same banner
    // twice.
    foregroundPushes.value = null;
    final route = push.route;
    final l10n = AppLocalizations.of(context);
    final text = [
      push.title,
      push.body,
    ].where((s) => s.trim().isNotEmpty).join(' — ');
    if (text.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
          duration: const Duration(seconds: 5),
          action: route == null
              ? null
              : SnackBarAction(
                  label: l10n.commonView,
                  onPressed: () {
                    if (mounted && isValidPushRoute(route)) {
                      context.push(route);
                    }
                  },
                ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Tab 1 is the Discover branch. Until ops turns the flag on it presents as
    // the Social tab it has always been — same label, same glyph, same
    // destination — so an un-flagged build is indistinguishable from today's
    // (DISCOVER spec §4, and the rollback lever in §30). The flag arrives
    // asynchronously, so the first frame of a cold start shows Social and
    // settles to Discover once the backend answers; that is the same
    // load-then-settle the community surface already has.
    final discover = ref.watch(featureEnabledProvider(FeatureFlags.discover));
    return WtmScaffold(
      // Content scrolls under the translucent nav wash (board .navbar).
      extendBody: true,
      body: widget.shell,
      bottomNavigationBar: WtmBottomNav(
        items: [
          WtmNavItem(glyph: WtmGlyph.home, label: l10n.wtmNavHome),
          WtmNavItem(
            glyph: discover ? WtmGlyph.compass : WtmGlyph.users,
            label: discover ? l10n.wtmNavDiscover : l10n.wtmNavSocial,
          ),
          WtmNavItem(glyph: WtmGlyph.inbox, label: l10n.wtmNavInbox),
          WtmNavItem(glyph: WtmGlyph.user, label: l10n.wtmNavProfile),
        ],
        currentIndex: widget.shell.currentIndex,
        onTap: (index) => widget.shell.goBranch(
          index,
          // Re-tapping the active tab resets it to its root (standard).
          initialLocation: index == widget.shell.currentIndex,
        ),
        onOrbTap: () => showUploadHubSheet(context),
        orbSemanticLabel: l10n.wtmNavOrb,
      ),
    );
  }
}
