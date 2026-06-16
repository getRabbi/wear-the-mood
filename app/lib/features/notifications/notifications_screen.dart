import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/push/push_messaging.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';

/// Activity inbox (redesign spec — Notifications). Surfaces likes, comments,
/// follows, try-on-ready, credit and premium messages. There's no notifications
/// backend yet, so it shows a clean, friendly empty state rather than a broken
/// screen (CLAUDE.md §4.3 — never a bare blank).
///
/// Opening this screen is the contextual moment we ask for the OS notification
/// permission (CLAUDE.md §20) — not on cold launch. Safe no-op without Firebase.
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationsTitle)),
      body: SafeArea(
        child: EmptyState(
          icon: Icons.notifications_none_rounded,
          title: l10n.notificationsEmptyTitle,
          message: l10n.notificationsEmptyMessage,
        ),
      ),
    );
  }
}
