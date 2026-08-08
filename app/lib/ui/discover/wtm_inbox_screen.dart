import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notifications/notification_routing.dart';
import '../../core/push/push_messaging.dart';
import '../../data/models/app_notification.dart';
import '../../data/repositories/notifications_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../paywall/wtm_topup_sheet.dart';
import '../widgets/widgets.dart';

/// WTM Inbox (board 15, P9) — the notification centre on [notificationsProvider],
/// split into Activity · Drops · System.
///
/// Type interpretation (section, icon, destination) lives in ONE place,
/// [NotificationRouting], mirroring the server's table. It used to be three sets
/// of `type.contains(...)` checks scattered across this file, which is how a new
/// event type could end up with the wrong icon, in the wrong tab, opening nothing.
class WtmInboxScreen extends ConsumerStatefulWidget {
  const WtmInboxScreen({super.key});

  @override
  ConsumerState<WtmInboxScreen> createState() => _WtmInboxScreenState();
}

class _WtmInboxScreenState extends ConsumerState<WtmInboxScreen>
    with WidgetsBindingObserver {
  NotificationSection _tab = NotificationSection.activity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A push may have landed while this list was off-screen, so reconcile with
    // the server on open rather than trusting whatever was cached.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(notificationsProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the background is when the list is most likely stale.
    // `mounted` guards a resume that lands after disposal.
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(notificationsProvider.notifier).refresh();
    }
  }

  Future<void> _open(AppNotification n) async {
    // Mark read first, so the badge is correct even if navigating replaces us.
    await ref.read(notificationsProvider.notifier).markRead(n.id);
    if (!mounted) return;

    // Credits open a sheet rather than a route, so that one is handled here;
    // every other destination comes from the shared mapping.
    if (n.targetType == NotificationTargets.credit) {
      showTopUpSheet(context);
      return;
    }
    final route = n.route;
    // An unknown or target-less notification is not an error — it is marked read
    // and simply has nowhere specific to open.
    if (route != null && isValidPushRoute(route)) context.push(route);
  }

  Future<void> _markAllRead() async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(notificationsProvider.notifier).markAllRead();
      if (mounted) wtmSnack(context, l10n.inboxAllRead);
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.errorGenericTitle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationCountProvider);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: WtmColors.gold,
        backgroundColor: WtmColors.panel,
        onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            WtmSpace.screenH,
            WtmSpace.s16,
            WtmSpace.screenH,
            wtmNavClearance,
          ),
          children: [
            Row(
              children: [
                Expanded(child: Text(l10n.wtmInboxTitle, style: WtmType.h1)),
                if (unread > 0)
                  GoldPill(label: l10n.inboxMarkAllRead, onTap: _markAllRead),
              ],
            ),
            const SizedBox(height: WtmSpace.s14),
            WtmChipRow(
              children: [
                for (final (i, label) in [
                  l10n.wtmInboxActivity,
                  l10n.wtmInboxDrops,
                  l10n.wtmInboxSystem,
                ].indexed)
                  WtmChip(
                    label: label,
                    on: _tab.index == i,
                    onTap: () =>
                        setState(() => _tab = NotificationSection.values[i]),
                  ),
              ],
            ),
            const SizedBox(height: WtmSpace.s14),
            ...async.when<List<Widget>>(
              skipLoadingOnReload: true,
              loading: () => const [
                LoadingShimmer(width: double.infinity, height: 56),
                SizedBox(height: 9),
                LoadingShimmer(width: double.infinity, height: 56),
              ],
              error: (_, _) => [
                WtmErrorState(
                  title: l10n.wtmInboxErrorTitle,
                  message: l10n.errorGenericTitle,
                  retryLabel: l10n.commonRetry,
                  onRetry: () =>
                      ref.read(notificationsProvider.notifier).refresh(),
                ),
              ],
              data: (feed) {
                final rows = [
                  for (final n in feed.items)
                    if (n.section == _tab) n,
                ];
                if (rows.isEmpty) {
                  return [
                    const SizedBox(height: WtmSpace.s22),
                    WtmEmptyState(
                      glyph: WtmGlyph.bell,
                      title: l10n.wtmInboxEmptyTitle,
                      message: l10n.wtmInboxEmptyMessage,
                    ),
                  ];
                }
                return [
                  for (final (i, n) in rows.indexed) ...[
                    if (i > 0) const SizedBox(height: 9),
                    _NotificationRow(notification: n, onTap: () => _open(n)),
                  ],
                  // Paging is per-FEED, not per-tab: the server returns every
                  // section in one stream, so "load older" fetches the next page
                  // of everything and the active tab filters it.
                  if (feed.hasMore) ...[
                    const SizedBox(height: WtmSpace.s14),
                    GhostButton(
                      label: l10n.inboxLoadMore,
                      onPressed: feed.loadingMore
                          ? null
                          : () => ref
                                .read(notificationsProvider.notifier)
                                .loadMore(),
                    ),
                  ],
                ];
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One row. Unread is carried by a gold dot AND the semantic label, so the state
/// is never signalled by colour alone (§4.4).
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unread = !notification.isRead;
    return Semantics(
      button: true,
      label: unread
          ? '${l10n.inboxUnread}. ${notification.title}'
          : notification.title,
      child: ExcludeSemantics(
        child: Stack(
          children: [
            WtmRow(
              glyph: notification.glyph,
              title: notification.title,
              subtitle: notification.body,
              onTap: onTap,
            ),
            if (unread)
              Positioned(
                top: WtmSpace.s12,
                right: WtmSpace.s12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: WtmColors.gold,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
