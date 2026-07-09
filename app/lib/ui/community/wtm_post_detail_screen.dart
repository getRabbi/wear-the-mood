import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../data/models/post.dart';
import '../../data/repositories/social_repository.dart';
import '../../features/social/social_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../profile/wtm_profile_photo.dart' show showWtmProfilePhotoViewer;
import '../widgets/widgets.dart';
import 'wtm_community_shared.dart';

/// WTM Post detail (board §3.11, P8) — the full post + real comments
/// ([postCommentsProvider]) + a composer that posts through the moderated
/// [SocialRepository.addComment]. Reached with the [Post] as the route extra.
class WtmPostDetailScreen extends ConsumerStatefulWidget {
  const WtmPostDetailScreen({super.key, required this.post});

  final Post post;

  @override
  ConsumerState<WtmPostDetailScreen> createState() =>
      _WtmPostDetailScreenState();
}

class _WtmPostDetailScreenState extends ConsumerState<WtmPostDetailScreen> {
  final _comment = TextEditingController();
  late bool _liked = widget.post.likedByMe;
  late int _likeCount = widget.post.likeCount;
  bool _busy = false;

  Post get _post => widget.post;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    final next = !_liked;
    setState(() {
      _liked = next;
      _likeCount += next ? 1 : -1;
    });
    try {
      final repo = ref.read(socialRepositoryProvider);
      await (next ? repo.like(_post.id) : repo.unlike(_post.id));
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked = !next;
          _likeCount += next ? -1 : 1;
        });
      }
    }
  }

  Future<void> _addComment() async {
    final body = _comment.text.trim();
    if (body.isEmpty || _busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(socialRepositoryProvider).addComment(_post.id, body);
      _comment.clear();
      ref.invalidate(postCommentsProvider(_post.id));
      ref.read(feedProvider.notifier).bumpCommentCount(_post.id);
      if (mounted) wtmSnack(context, l10n.wtmCommentDone);
    } on ApiException {
      if (mounted) wtmSnack(context, l10n.wtmCommentError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final commentsAsync = ref.watch(postCommentsProvider(_post.id));
    final image = _post.imageUrl ?? _post.thumbnailUrl;

    return WtmPage(
      title: l10n.wtmPostTitle,
      eyebrow: l10n.wtmSocialTitle,
      trailing: WtmIconButton(
        WtmGlyph.dots,
        semanticLabel: l10n.wtmSocialPostOptions,
        // Your own post gets manage actions, never Report/Block (QA #5).
        onTap: () => _post.userId == ref.watch(authUserIdProvider)
            ? showWtmOwnPostSheet(
                context,
                ref,
                post: _post,
                showView: false, // already on the post
                onDeleted: () => wtmPageBack(context),
              )
            : showWtmReportBlockSheet(
                context,
                ref,
                subjectType: 'post',
                subjectId: _post.id,
                userId: _post.userId,
                onBlocked: () {
                  ref.read(feedProvider.notifier).removeLocally(_post.id);
                  wtmPageBack(context);
                },
              ),
      ),
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push('${AppRoute.wtmUser}?u=${_post.userId}'),
          child: Row(
            children: [
              WtmAvatar(_post.authorName),
              const SizedBox(width: WtmSpace.s10),
              Expanded(
                child: Text(
                  _post.authorName ?? l10n.wtmSocialSomeone,
                  style: WtmType.labelMedium,
                ),
              ),
              Text(wtmPostTime(l10n, _post.createdAt), style: WtmType.micro),
            ],
          ),
        ),
        const SizedBox(height: WtmSpace.s12),
        // Media only when the post has some — text-only and poll posts carry
        // their content directly (no blank gradient hero). The FULL image
        // shows (contain, capped height); tap → the zoomable full-screen
        // viewer (mobile QA #5 — never crop heads/feet off a try-on).
        if (image != null) ...[
          Semantics(
            button: true,
            label: l10n.wtmLooksView,
            child: ExcludeSemantics(
              child: GestureDetector(
                onTap: () =>
                    showWtmProfilePhotoViewer(context, ref, url: image),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(WtmRadius.tile),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 560),
                    color: WtmColors.iconBtnBg,
                    alignment: Alignment.center,
                    child: CachedNetworkImage(
                      imageUrl: image,
                      cacheKey: stableImageCacheKey(image),
                      width: double.infinity,
                      fit: BoxFit.contain,
                      // Decode at display size, not full-res (mobile QA #1).
                      memCacheWidth: 1080,
                      placeholder: (_, _) =>
                          const AuroraBox(height: 260, vignette: true),
                      errorWidget: (_, _, _) =>
                          const AuroraBox(height: 260, vignette: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: WtmSpace.s10),
        ],
        if (image == null && (_post.caption ?? '').trim().isNotEmpty) ...[
          Text(
            _post.caption!.trim(),
            style: WtmType.h2.copyWith(fontSize: 17, height: 1.45),
          ),
          const SizedBox(height: WtmSpace.s10),
        ],
        if (_post.poll != null) ...[
          WtmPollView(poll: _post.poll!),
          const SizedBox(height: WtmSpace.s10),
        ],
        Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleLike,
              child: Row(
                children: [
                  WtmIcon(
                    WtmGlyph.heart,
                    size: 15,
                    color: _liked ? WtmColors.gold : WtmColors.muted,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$_likeCount',
                    style: WtmType.chip.copyWith(
                      color: _liked ? WtmColors.gold : WtmColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: WtmSpace.s14),
            Row(
              children: [
                const WtmIcon(
                  WtmGlyph.comment,
                  size: 15,
                  color: WtmColors.muted,
                ),
                const SizedBox(width: 5),
                Text('${_post.commentCount}', style: WtmType.chip),
              ],
            ),
          ],
        ),
        // Caption under the actions — only when it wasn't already the hero
        // content above (text-only posts).
        if (image != null && (_post.caption ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: WtmSpace.s8),
          Text(
            _post.caption!.trim(),
            style: WtmType.body.copyWith(fontSize: 12, height: 1.5),
          ),
        ],
        const SizedBox(height: WtmSpace.s14),
        const Divider(color: WtmColors.lineSoft, height: 1),
        const SizedBox(height: WtmSpace.s12),
        EyebrowLabel(l10n.wtmPostComments),
        const SizedBox(height: WtmSpace.s10),
        ...commentsAsync.when<List<Widget>>(
          skipLoadingOnReload: true,
          loading: () => const [
            LoadingShimmer(width: double.infinity, height: 40),
          ],
          error: (_, _) => [
            Text(l10n.wtmPostCommentsError, style: WtmType.micro),
          ],
          data: (comments) => comments.isEmpty
              ? [Text(l10n.wtmPostNoComments, style: WtmType.micro)]
              : [
                  for (final (i, c) in comments.indexed) ...[
                    if (i > 0) const SizedBox(height: WtmSpace.s10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () =>
                              context.push('${AppRoute.wtmUser}?u=${c.userId}'),
                          child: WtmAvatar(c.authorName, size: 26),
                        ),
                        const SizedBox(width: WtmSpace.s8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.authorName ?? l10n.wtmSocialSomeone,
                                style: WtmType.micro.copyWith(
                                  color: WtmColors.gold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(c.body, style: WtmType.sub),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
        ),
        const SizedBox(height: WtmSpace.s14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _comment,
                style: WtmType.body.copyWith(fontSize: 12.5),
                cursorColor: WtmColors.gold,
                onSubmitted: (_) => _addComment(),
                decoration: InputDecoration(
                  hintText: l10n.wtmPostAddComment,
                  hintStyle: WtmType.body.copyWith(
                    fontSize: 12.5,
                    color: WtmColors.faint,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: WtmColors.iconBtnBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(WtmRadius.chip),
                    borderSide: const BorderSide(color: WtmColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(WtmRadius.chip),
                    borderSide: const BorderSide(color: WtmColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(WtmRadius.chip),
                    borderSide: const BorderSide(color: WtmColors.chipOnBorder),
                  ),
                ),
              ),
            ),
            const SizedBox(width: WtmSpace.s8),
            GoldPill(
              label: l10n.wtmPostSend,
              onTap: _busy ? null : _addComment,
            ),
          ],
        ),
      ],
    );
  }
}
