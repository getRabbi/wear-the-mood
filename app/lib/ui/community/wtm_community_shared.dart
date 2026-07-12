import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../data/models/poll.dart';
import '../../data/models/post.dart';
import '../../data/repositories/social_repository.dart';
import '../../features/social/social_providers.dart';
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

  void toggle(String id) =>
      state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
}

final wtmSavedPostsProvider = NotifierProvider<WtmSavedPosts, Set<String>>(
  WtmSavedPosts.new,
);

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
      final updated = await ref
          .read(socialRepositoryProvider)
          .votePoll(_poll.id, index);
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
                child: Text(
                  _poll.question,
                  style: WtmType.labelMedium.copyWith(fontSize: 13.5),
                ),
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
                color: mine ? WtmColors.chipOnBorder : WtmColors.line,
              ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      if (mine) ...[
                        const WtmIcon(
                          WtmGlyph.check,
                          size: 12,
                          color: WtmColors.gold,
                        ),
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

/// The ⋯ sheet for the user's OWN post (mobile QA #5): View / Edit caption /
/// Delete — never Report/Block on yourself. Edit is offered only for posts the
/// deployed backend can PATCH (image or outfit posts; the edit endpoint still
/// requires visible media). [onDeleted] lets the caller pop/refresh.
Future<void> showWtmOwnPostSheet(
  BuildContext context,
  WidgetRef ref, {
  required Post post,
  bool showView = true,
  VoidCallback? onDeleted,
}) {
  final l10n = AppLocalizations.of(context);
  final canEdit = post.imageUrl != null || post.outfitId != null;

  Future<void> editCaption() async {
    Navigator.of(context).pop();
    final controller = TextEditingController(text: post.caption ?? '');
    var saved = false;
    await showWtmSheet(
      context,
      title: l10n.wtmOwnPostEdit,
      children: [
        Builder(
          builder: (sheetContext) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                maxLines: 3,
                maxLength: 400,
                autofocus: true,
                style: WtmType.body,
                cursorColor: WtmColors.gold,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: l10n.wtmOwnPostEditHint,
                  hintStyle: WtmType.body.copyWith(color: WtmColors.faint),
                  filled: true,
                  fillColor: WtmColors.iconBtnBg,
                  counterStyle: WtmType.micro,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(WtmRadius.button),
                    borderSide: const BorderSide(color: WtmColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(WtmRadius.button),
                    borderSide: const BorderSide(color: WtmColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(WtmRadius.button),
                    borderSide: const BorderSide(color: WtmColors.chipOnBorder),
                  ),
                ),
              ),
              const SizedBox(height: WtmSpace.s12),
              GradientCta(
                label: l10n.wtmOwnPostEditSave,
                onPressed: () {
                  saved = true;
                  Navigator.of(sheetContext).pop();
                },
              ),
            ],
          ),
        ),
      ],
    );
    if (!saved || !context.mounted) return;
    try {
      final caption = controller.text.trim();
      await ref
          .read(socialRepositoryProvider)
          .editPost(
            post.id,
            caption: caption.isEmpty ? null : caption,
            imageUrl: post.imageUrl,
            outfitId: post.outfitId,
            tags: post.tags,
          );
      await ref.read(feedProvider.notifier).refresh();
      if (context.mounted) wtmSnack(context, l10n.wtmOwnPostEditSaved);
    } on ApiException catch (e) {
      if (context.mounted) wtmSnack(context, e.message);
    } catch (_) {
      if (context.mounted) wtmSnack(context, l10n.wtmComposeError);
    } finally {
      controller.dispose();
    }
  }

  Future<void> deletePost() async {
    Navigator.of(context).pop();
    final confirmed = await wtmConfirmDialog(
      context,
      title: l10n.wtmOwnPostDeleteConfirmTitle,
      message: l10n.wtmOwnPostDeleteConfirmBody,
      confirmLabel: l10n.wtmOwnPostDelete,
      danger: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(socialRepositoryProvider).deletePost(post.id);
      ref.read(feedProvider.notifier).removeLocally(post.id);
      onDeleted?.call();
      if (context.mounted) wtmSnack(context, l10n.wtmOwnPostDeleted);
    } on ApiException catch (e) {
      if (context.mounted) wtmSnack(context, e.message);
    }
  }

  return showWtmSheet(
    context,
    title: l10n.wtmOwnPostTitle,
    subtitle: l10n.wtmOwnPostSubtitle,
    children: [
      if (showView) ...[
        WtmRow(
          glyph: WtmGlyph.image,
          title: l10n.wtmOwnPostView,
          onTap: () {
            Navigator.of(context).pop();
            context.push(AppRoute.wtmPost, extra: post);
          },
        ),
        const SizedBox(height: 9),
      ],
      if (canEdit) ...[
        WtmRow(
          glyph: WtmGlyph.sparkle,
          title: l10n.wtmOwnPostEdit,
          onTap: editCaption,
        ),
        const SizedBox(height: 9),
      ],
      WtmRow(
        glyph: WtmGlyph.erase,
        title: l10n.wtmOwnPostDelete,
        titleColor: WtmColors.danger,
        iconColor: WtmColors.danger,
        onTap: deletePost,
      ),
    ],
  );
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
      await ref
          .read(socialRepositoryProvider)
          .report(
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
      // Store-review reason set (Apple UGC guideline 1.2) — stored server-side
      // as the reason string, so extending the list needs no backend change.
      for (final reason in [
        l10n.wtmReportInappropriate,
        l10n.wtmReportSpam,
        l10n.wtmReportHarassment,
        l10n.wtmReportNudity,
        l10n.wtmReportViolence,
        l10n.wtmReportHate,
        l10n.wtmReportScam,
        l10n.wtmReportIp,
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
