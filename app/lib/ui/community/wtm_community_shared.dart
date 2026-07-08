import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/poll.dart';
import '../../data/repositories/social_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// A circular avatar (community rows/cards): the creator's photo when one is
/// available ([imageUrl], e.g. a public profile's display picture), else the
/// gold monogram on the signature aurora fill.
class WtmAvatar extends StatelessWidget {
  const WtmAvatar(this.name, {super.key, this.size = 34, this.imageUrl});

  final String? name;
  final double size;
  final String? imageUrl;

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
    final monogram = Text(
      initials,
      style: WtmType.labelMedium.copyWith(
        color: WtmColors.gold,
        fontSize: size * 0.42,
      ),
    );
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: WtmGradients.assistFill,
        border: Border.all(color: WtmColors.pillBorder),
      ),
      child: (imageUrl == null || imageUrl!.isEmpty)
          ? monogram
          : CachedNetworkImage(
              imageUrl: imageUrl!,
              cacheKey: stableImageCacheKey(imageUrl!),
              fit: BoxFit.cover,
              width: size,
              height: size,
              // Avatars are tiny — never decode a full-size photo for them.
              memCacheWidth: (size * 3).round(),
              placeholder: (_, _) => monogram,
              errorWidget: (_, _, _) => monogram,
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

/// A poll on a post card / detail (FEATURES_COMMUNITY_PLUS · Poll, WTM dress).
/// Before voting the options are tappable pills; after voting (or once closed)
/// it shows gold result bars with counts, highlighting the viewer's choice.
/// Holds the latest poll locally so a vote updates in place without a refetch.
class WtmPollView extends ConsumerStatefulWidget {
  const WtmPollView({super.key, required this.poll});

  final Poll poll;

  @override
  ConsumerState<WtmPollView> createState() => _WtmPollViewState();
}

class _WtmPollViewState extends ConsumerState<WtmPollView> {
  late Poll _poll = widget.poll;
  bool _voting = false;

  @override
  void didUpdateWidget(WtmPollView old) {
    super.didUpdateWidget(old);
    // Reseed from a refreshed feed (pull-to-refresh brought newer counts).
    if (widget.poll != old.poll) _poll = widget.poll;
  }

  Future<void> _vote(int index) async {
    if (_voting || _poll.showResults) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _voting = true);
    try {
      final updated =
          await ref.read(socialRepositoryProvider).votePoll(_poll.id, index);
      await ref.read(analyticsProvider).track(AnalyticsEvents.pollVoted);
      if (mounted) setState(() => _poll = updated);
    } on ApiException {
      if (mounted) wtmSnack(context, l10n.pollVoteError);
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showResults = _poll.showResults;
    return Container(
      padding: const EdgeInsets.all(WtmSpace.s12),
      decoration: BoxDecoration(
        color: WtmColors.iconBtnBg,
        borderRadius: BorderRadius.circular(WtmRadius.tile),
        border: Border.all(color: WtmColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const WtmIcon(WtmGlyph.sparkle, size: 15, color: WtmColors.gold),
              const SizedBox(width: WtmSpace.s8),
              Expanded(
                child: Text(_poll.question,
                    style: WtmType.labelMedium.copyWith(fontSize: 13.5)),
              ),
            ],
          ),
          const SizedBox(height: WtmSpace.s10),
          for (final option in _poll.options) ...[
            _PollOptionRow(
              label: option.label,
              votes: option.votes,
              total: _poll.totalVotes,
              showResults: showResults,
              mine: _poll.myChoice == option.index,
              onTap: (_voting || showResults)
                  ? null
                  : () => _vote(option.index),
            ),
            const SizedBox(height: WtmSpace.s8),
          ],
          Text(
            _poll.isClosed
                ? '${l10n.pollTotalVotes(_poll.totalVotes)} · ${l10n.pollClosed}'
                : l10n.pollTotalVotes(_poll.totalVotes),
            style: WtmType.micro,
          ),
        ],
      ),
    );
  }
}

class _PollOptionRow extends StatelessWidget {
  const _PollOptionRow({
    required this.label,
    required this.votes,
    required this.total,
    required this.showResults,
    required this.mine,
    required this.onTap,
  });

  final String label;
  final int votes;
  final int total;
  final bool showResults;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(WtmRadius.chip);

    if (!showResults) {
      // Pre-vote: a tappable hairline option.
      return Semantics(
        button: true,
        label: label,
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 40),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: WtmColors.pillBorder),
                color: WtmColors.pillBg,
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WtmType.label.copyWith(color: WtmColors.gold),
              ),
            ),
          ),
        ),
      );
    }

    // Post-vote / closed: a result bar with share of votes.
    final share = total <= 0 ? 0.0 : votes / total;
    return Semantics(
      label: '$label: $votes',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: radius,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 40),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                  color: mine ? WtmColors.chipOnBorder : WtmColors.line),
              color: WtmColors.chipBg,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: share.clamp(0.0, 1.0),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(color: WtmColors.chipOnBg),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      if (mine) ...[
                        const WtmIcon(WtmGlyph.check,
                            size: 12, color: WtmColors.gold),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WtmType.label.copyWith(
                            color: mine ? WtmColors.gold : WtmColors.text,
                          ),
                        ),
                      ),
                      Text('${(share * 100).round()}%', style: WtmType.micro),
                    ],
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
