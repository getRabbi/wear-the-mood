import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/push/push_messaging.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/app_notification.dart';
import '../../data/repositories/notifications_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';

/// Activity inbox (CLAUDE.md §1 pillar 4) — likes, comments, follows, try-on
/// updates, credits/premium and system messages. Real feed with unread dots,
/// mark-all-read, pull-to-refresh and the four states (§4.3). Works fully
/// without FCM (this is in-app data, not push).
///
/// Opening this screen is also the contextual moment we ask for the OS
/// notification permission (CLAUDE.md §20) — never on cold launch. Safe no-op
/// without Firebase.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pushMessagingProvider).promptPermission();
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _markAllRead() async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(notificationsRepositoryProvider).markAllRead();
      ref.invalidate(notificationsProvider);
    } on ApiException {
      _snack(l10n.notificationActionError);
    }
  }

  /// Mark a notification read, then route to the relevant place where one
  /// exists. Unknown/route-less types just clear (never crash).
  Future<void> _open(AppNotification n) async {
    // Optimistic mark-read.
    if (!n.isRead) {
      ref.read(notificationsRepositoryProvider).markRead(n.id).ignore();
      ref.invalidate(notificationsProvider);
    }
    switch (n.type) {
      case 'follow':
        final id = n.targetId ?? n.actorId;
        if (id != null && id.isNotEmpty) {
          context.push(AppRoute.userProfilePath(id));
        }
      case 'try_on_ready':
        context.push(AppRoute.tryonHistory);
      case 'credit_update':
      case 'premium':
        context.push(AppRoute.paywall);
      default:
        // like / comment / community / challenge / system notifications have no
        // dedicated destination — opening the list and marking them read is the
        // action (deliberate; a post-detail route can deep-link here later).
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final feed = ref.watch(notificationsProvider);
    final hasUnread = ref.watch(unreadNotificationsProvider) > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notificationsTitle),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: Text(l10n.notificationsMarkAllRead),
            ),
        ],
      ),
      body: SafeArea(
        child: feed.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorState(
            title: l10n.notificationsErrorTitle,
            onRetry: () => ref.invalidate(notificationsProvider),
            retryLabel: l10n.commonRetry,
          ),
          data: (items) {
            if (items.isEmpty) {
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(notificationsProvider),
                child: ListView(
                  children: [
                    const SizedBox(height: AppSpace.xxl),
                    EmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: l10n.notificationsEmptyTitle,
                      message: l10n.notificationsEmptyMessage,
                    ),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(notificationsProvider),
              child: ListView.separated(
                padding: EdgeInsets.only(bottom: bottomNavClearance(context)),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) =>
                    _NotificationTile(item: items[i], onTap: () => _open(items[i])),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  ({IconData icon, Color color}) get _visual => switch (item.type) {
    'like' => (icon: Icons.favorite_rounded, color: AppColors.accent),
    'comment' => (icon: Icons.mode_comment_rounded, color: AppColors.lavender),
    'follow' => (icon: Icons.person_add_rounded, color: AppColors.violet),
    'try_on_ready' => (icon: Icons.auto_awesome_rounded, color: AppColors.accent),
    'credit_update' => (icon: Icons.bolt_rounded, color: AppColors.warn),
    'premium' => (icon: Icons.workspace_premium_rounded, color: AppColors.accent),
    'challenge' => (icon: Icons.emoji_events_rounded, color: AppColors.warn),
    'community' => (icon: Icons.groups_rounded, color: AppColors.lavender),
    _ => (icon: Icons.notifications_rounded, color: AppColors.graphite),
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final v = _visual;
    return ListTile(
      onTap: onTap,
      // A soft tint marks an unread row, plus the trailing dot.
      tileColor: item.isRead ? null : AppColors.accentSoft.withValues(alpha: 0.10),
      leading: CircleAvatar(
        backgroundColor: v.color.withValues(alpha: 0.16),
        child: Icon(v.icon, color: v.color, size: 20),
      ),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.titleMedium?.copyWith(
          fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w700,
        ),
      ),
      subtitle: Text(
        [
          if ((item.body ?? '').trim().isNotEmpty) item.body!.trim(),
          _timeAgo(item.createdAt),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: text.bodySmall,
      ),
      trailing: item.isRead
          ? null
          : Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
            ),
    );
  }
}

/// Compact relative timestamp (e.g. "3h", "2d").
String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${(diff.inDays / 7).floor()}w';
}
