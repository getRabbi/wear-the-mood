import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../data/models/app_notification.dart';
import '../../data/repositories/notifications_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../paywall/wtm_topup_sheet.dart';
import '../widgets/widgets.dart';

enum _Inbox { activity, drops, system }

/// WTM Inbox (board 15, P9) — the notification centre on the real
/// [notificationsProvider], split into Activity · Drops · System. Tapping a row
/// marks it read and deep-links to its target — the **Drops** rows open the
/// giveaway / offer / article (the P9 gate).
class WtmInboxScreen extends ConsumerStatefulWidget {
  const WtmInboxScreen({super.key});

  @override
  ConsumerState<WtmInboxScreen> createState() => _WtmInboxScreenState();
}

class _WtmInboxScreenState extends ConsumerState<WtmInboxScreen> {
  _Inbox _tab = _Inbox.activity;

  static _Inbox _kindOf(AppNotification n) {
    final t = (n.targetType ?? n.type).toLowerCase();
    if (t.contains('giveaway') || t.contains('offer') || t.contains('news')) {
      return _Inbox.drops;
    }
    if (t.contains('post') ||
        t.contains('user') ||
        t.contains('comment') ||
        t.contains('like') ||
        t.contains('follow')) {
      return _Inbox.activity;
    }
    return _Inbox.system;
  }

  WtmGlyph _glyph(AppNotification n) {
    final t = (n.targetType ?? n.type).toLowerCase();
    if (t.contains('like')) return WtmGlyph.heart;
    if (t.contains('follow') || t.contains('user')) return WtmGlyph.users;
    if (t.contains('comment')) return WtmGlyph.comment;
    if (t.contains('giveaway')) return WtmGlyph.gift;
    if (t.contains('offer')) return WtmGlyph.store;
    if (t.contains('news')) return WtmGlyph.image;
    if (t.contains('credit')) return WtmGlyph.coin;
    if (t.contains('subscription')) return WtmGlyph.sparkle;
    if (t.contains('moderation')) return WtmGlyph.shield;
    return WtmGlyph.bell;
  }

  void _open(AppNotification n) {
    // Mark read (fire-and-forget) + refresh the unread badge.
    ref.read(notificationsRepositoryProvider).markRead(n.id);
    ref.invalidate(notificationsProvider);

    final id = n.targetId;
    switch ((n.targetType ?? '').toLowerCase()) {
      case 'giveaway' when id != null:
        context.push('${AppRoute.wtmGiveawayDetail}?id=$id');
      case 'offer' when id != null:
        context.push('${AppRoute.wtmOfferDetail}?id=$id');
      case 'news' when id != null:
        context.push('${AppRoute.wtmArticle}?id=$id');
      case 'user' when id != null:
        context.push('${AppRoute.wtmUser}?u=$id');
      case 'credit':
        showTopUpSheet(context);
      case 'subscription':
        context.push(AppRoute.wtmPaywall);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notifsAsync = ref.watch(notificationsProvider);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          WtmSpace.screenH,
          WtmSpace.s16,
          WtmSpace.screenH,
          wtmNavClearance,
        ),
        children: [
          Text(l10n.wtmInboxTitle, style: WtmType.h1),
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
                  onTap: () => setState(() => _tab = _Inbox.values[i]),
                ),
            ],
          ),
          const SizedBox(height: WtmSpace.s14),
          ...notifsAsync.when<List<Widget>>(
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
                onRetry: () => ref.invalidate(notificationsProvider),
              ),
            ],
            data: (all) {
              final rows = [for (final n in all) if (_kindOf(n) == _tab) n];
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
                  WtmRow(
                    glyph: _glyph(n),
                    title: n.title,
                    subtitle: n.body,
                    onTap: () => _open(n),
                  ),
                ],
              ];
            },
          ),
        ],
      ),
    );
  }
}
