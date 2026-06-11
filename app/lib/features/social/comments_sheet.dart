import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/social_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'social_providers.dart';

/// Bottom sheet to read and add comments on a post (CLAUDE.md §1 pillar 4).
/// Open with [showCommentsSheet].
Future<void> showCommentsSheet(BuildContext context, String postId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => CommentsSheet(postId: postId),
  );
}

class CommentsSheet extends ConsumerStatefulWidget {
  const CommentsSheet({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _sending) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _sending = true);
    try {
      await ref.read(socialRepositoryProvider).addComment(widget.postId, body);
      _controller.clear();
      ref.read(feedProvider.notifier).bumpCommentCount(widget.postId);
      ref.invalidate(postCommentsProvider(widget.postId));
    } on ApiException catch (error) {
      if (mounted) {
        _snack(
          error.code == ApiErrorCode.moderationBlocked
              ? l10n.commentBlocked
              : l10n.commentError,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final comments = ref.watch(postCommentsProvider(widget.postId));

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Text(l10n.commentsTitle, style: text.titleMedium),
            ),
            const Divider(height: 1),
            Expanded(
              child: comments.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => ErrorState(
                  title: l10n.commentsErrorTitle,
                  onRetry: () =>
                      ref.invalidate(postCommentsProvider(widget.postId)),
                ),
                data: (list) => list.isEmpty
                    ? EmptyState(
                        icon: Icons.mode_comment_outlined,
                        title: l10n.commentsEmpty,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.md,
                        ),
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final c = list[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              c.authorName ?? l10n.socialSomeone,
                              style: text.labelLarge,
                            ),
                            subtitle: Text(c.body, style: text.bodyMedium),
                          );
                        },
                      ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: l10n.commentHint,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
