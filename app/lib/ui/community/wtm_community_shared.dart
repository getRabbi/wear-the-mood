import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../data/repositories/social_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// A circular initials avatar (community rows/cards). Gold monogram on the
/// signature aurora fill — the community has no uploaded avatars yet.
class WtmAvatar extends StatelessWidget {
  const WtmAvatar(this.name, {super.key, this.size = 34});

  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final clean = (name ?? '').trim();
    final initials = clean.isEmpty
        ? '·'
        : clean
            .split(RegExp(r'\s+'))
            .take(2)
            .map((w) => w.isEmpty ? '' : w[0].toUpperCase())
            .join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: WtmGradients.assistFill,
        border: Border.all(color: WtmColors.pillBorder),
      ),
      child: Text(
        initials,
        style: WtmType.labelMedium.copyWith(
          color: WtmColors.gold,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

/// Compact relative time for a post/comment (e.g. "now", "5m", "3h", "2d").
String wtmPostTime(AppLocalizations l10n, DateTime createdAt) {
  final d = DateTime.now().difference(createdAt);
  if (d.inMinutes < 1) return l10n.wtmTimeNow;
  if (d.inMinutes < 60) return l10n.wtmTimeMinutes(d.inMinutes);
  if (d.inHours < 24) return l10n.wtmTimeHours(d.inHours);
  return l10n.wtmTimeDays(d.inDays);
}

/// Locally bookmarked post ids (Saved). Keep-alive so bookmarks survive tab
/// switches; the Saved-posts screen resolves them against the loaded feed.
class WtmSavedPosts extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  bool contains(String id) => state.contains(id);

  void toggle(String id) => state =
      state.contains(id) ? ({...state}..remove(id)) : {...state, id};
}

final wtmSavedPostsProvider =
    NotifierProvider<WtmSavedPosts, Set<String>>(WtmSavedPosts.new);

/// Report / Block sheet (board §3.14 — App Store hard requirement for UGC).
/// Files a real moderation report (§19) and blocks on the real endpoint; the
/// [onBlocked] callback hides the subject's content immediately (the P8 gate).
Future<void> showWtmReportBlockSheet(
  BuildContext context,
  WidgetRef ref, {
  required String subjectType, // 'post' | 'user'
  required String subjectId,
  required String userId,
  VoidCallback? onBlocked,
}) {
  final l10n = AppLocalizations.of(context);

  Future<void> report(String reason) async {
    Navigator.of(context).pop();
    try {
      await ref.read(socialRepositoryProvider).report(
            subjectType: subjectType,
            subjectId: subjectId,
            reason: reason,
          );
      if (context.mounted) wtmSnack(context, l10n.wtmReportDone);
    } on ApiException {
      if (context.mounted) wtmSnack(context, l10n.wtmReportError);
    }
  }

  Future<void> block() async {
    Navigator.of(context).pop();
    try {
      await ref.read(socialRepositoryProvider).block(userId);
      onBlocked?.call();
      if (context.mounted) wtmSnack(context, l10n.wtmBlockDone);
    } on ApiException {
      if (context.mounted) wtmSnack(context, l10n.wtmReportError);
    }
  }

  return showWtmSheet(
    context,
    title: l10n.wtmReportTitle,
    subtitle: l10n.wtmReportSubtitle,
    children: [
      for (final reason in [
        l10n.wtmReportInappropriate,
        l10n.wtmReportSpam,
        l10n.wtmReportHarassment,
        l10n.wtmReportOther,
      ]) ...[
        WtmRow(
          glyph: WtmGlyph.shield,
          title: reason,
          onTap: () => report(reason),
        ),
        const SizedBox(height: 9),
      ],
      WtmRow(
        glyph: WtmGlyph.user,
        title: l10n.wtmBlockUser,
        subtitle: l10n.wtmBlockUserSub,
        titleColor: WtmColors.danger,
        iconColor: WtmColors.danger,
        onTap: block,
      ),
    ],
  );
}
