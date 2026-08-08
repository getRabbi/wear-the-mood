import 'package:flutter/material.dart';

import 'wtm_discover_artwork.dart';
import 'wtm_story_rail.dart';
import '../../features/discover/domain/discover_story.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// What the viewer reports back when it closes.
class WtmStoryViewerResult {
  const WtmStoryViewerResult({required this.destination, this.story});

  /// The route the user chose to open, or null if they simply closed.
  final String? destination;

  /// The story that was on screen when the action was taken.
  final DiscoverStory? story;
}

/// Opens the Discover Story viewer over the current route (§7).
///
/// Returns the chosen destination, if any. Navigation is deliberately left to
/// the CALLER: the viewer has to be dismissed before the destination is
/// pushed, otherwise the user lands back inside a full-screen story when they
/// come back.
Future<WtmStoryViewerResult?> showWtmStoryViewer(
  BuildContext context, {
  required List<DiscoverStory> stories,
  required int initialIndex,
  required void Function(DiscoverStory story) onStoryShown,
  required void Function(DiscoverStory story, String action) onAction,
}) {
  return Navigator.of(context, rootNavigator: true).push<WtmStoryViewerResult>(
    PageRouteBuilder<WtmStoryViewerResult>(
      opaque: false,
      barrierColor: Colors.black87,
      transitionDuration: WtmMotion.base,
      pageBuilder: (_, _, _) => WtmStoryViewer(
        stories: stories,
        initialIndex: initialIndex,
        onStoryShown: onStoryShown,
        onAction: onAction,
      ),
      transitionsBuilder: (context, animation, _, child) {
        // Reduced motion gets the content without the slide (§6.6).
        if (MediaQuery.of(context).disableAnimations) {
          return FadeTransition(opacity: animation, child: child);
        }
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
                .animate(
                  CurvedAnimation(parent: animation, curve: WtmMotion.easing),
                ),
            child: child,
          ),
        );
      },
    ),
  );
}

/// Full-screen Discover Story viewer (§7).
///
/// Manual navigation only. There is no auto-advance and no autoplay video in
/// this version by design (§7.4) — the progress indicators show POSITION, not
/// a countdown, so nothing moves under the user while they are reading.
class WtmStoryViewer extends StatefulWidget {
  const WtmStoryViewer({
    super.key,
    required this.stories,
    required this.initialIndex,
    required this.onStoryShown,
    required this.onAction,
  });

  final List<DiscoverStory> stories;
  final int initialIndex;

  /// Fired when a story's content is actually on screen. This is what marks a
  /// story seen — a story that failed to load must never be marked (§6.5).
  ///
  /// In Phase 2 a story arrives fully materialized with the rail, so "shown"
  /// and "loaded" are the same moment: there is no per-story fetch that could
  /// fail, and a missing image is not a failure — it falls back to the aurora
  /// artwork by design. When a later phase gives a story type its own fetch
  /// (Today's Edit, Closet Match), this callback is the seam that must move
  /// behind it rather than firing on page display.
  final void Function(DiscoverStory story) onStoryShown;

  final void Function(DiscoverStory story, String action) onAction;

  @override
  State<WtmStoryViewer> createState() => _WtmStoryViewerState();
}

class _WtmStoryViewerState extends State<WtmStoryViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void initState() {
    super.initState();
    // The first story is already on screen when the viewer opens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _announce(_index));
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _announce(int index) {
    if (!mounted || index < 0 || index >= widget.stories.length) return;
    widget.onStoryShown(widget.stories[index]);
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.stories.length) return;
    _pages.animateToPage(
      index,
      duration: WtmMotion.fast,
      curve: WtmMotion.easing,
    );
  }

  void _close([WtmStoryViewerResult? result]) {
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  void _openDestination(DiscoverStory story) {
    widget.onAction(story, story.destination.route);
    _close(
      WtmStoryViewerResult(destination: story.destination.route, story: story),
    );
  }

  /// The default CTA for a story type (§7.3). A story may override it.
  String _ctaLabel(AppLocalizations l10n, DiscoverStory story) {
    final custom = story.destination.label;
    if (custom != null && custom.trim().isNotEmpty) return custom;
    return switch (story.type) {
      DiscoverStoryType.giveaway => l10n.wtmStoryCtaViewGiveaway,
      DiscoverStoryType.offer => l10n.wtmStoryCtaViewOffer,
      DiscoverStoryType.newsroom => l10n.wtmStoryCtaReadStory,
      // The personalized types arrive with Phase 3; until they carry their own
      // label this is an honest generic rather than a promise we cannot keep.
      _ => l10n.wtmStoryCtaOpen,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final story = widget.stories[_index];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PopScope(
        // Back exits the viewer safely rather than the whole branch (§7.2).
        canPop: true,
        child: GestureDetector(
          // Swipe down to dismiss (§7.2). Only a decisive downward flick — a
          // small drag should not close something the user is reading.
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) > 320) _close();
          },
          child: Stack(
            children: [
              PageView.builder(
                controller: _pages,
                itemCount: widget.stories.length,
                onPageChanged: (index) {
                  setState(() => _index = index);
                  _announce(index);
                },
                itemBuilder: (context, index) =>
                    _StoryPage(story: widget.stories[index]),
              ),
              // Tap zones: left = previous, right = next (§7.2). Behind the
              // controls and the CTA, so those keep their own taps.
              Positioned.fill(
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: l10n.wtmStoryPrevious,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => _goTo(_index - 1),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: l10n.wtmStoryNext,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => _goTo(_index + 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WtmSpace.s14),
                  child: Column(
                    children: [
                      const SizedBox(height: WtmSpace.s10),
                      Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              label: l10n.wtmStoryPosition(
                                _index + 1,
                                widget.stories.length,
                              ),
                              child: ExcludeSemantics(
                                child: _ProgressBar(
                                  count: widget.stories.length,
                                  index: _index,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: WtmSpace.s10),
                          WtmIconButton(
                            WtmGlyph.back,
                            semanticLabel: l10n.wtmStoryClose,
                            onTap: _close,
                          ),
                        ],
                      ),
                      const Spacer(),
                      _StoryFooter(
                        story: story,
                        ctaLabel: _ctaLabel(l10n, story),
                        onCta: () => _openDestination(story),
                      ),
                      const SizedBox(height: WtmSpace.s22),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Position indicators — one segment per story, the current one filled.
/// Deliberately not animated: a moving bar reads as a countdown, and there is
/// no auto-advance to count down to (§7.4).
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 2.5,
              decoration: BoxDecoration(
                color: i == index ? WtmColors.gold : WtmColors.line,
                borderRadius: BorderRadius.circular(WtmRadius.chip),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The full-bleed visual for one story.
class _StoryPage extends StatelessWidget {
  const _StoryPage({required this.story});

  final DiscoverStory story;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-bleed, and never a flat panel: a story opened on a failed image
        // used to be an empty violet screen with the copy floating on it.
        WtmDiscoverArtwork(
          url: story.imageUrl,
          seed: story.type.name,
          glyph: wtmStoryGlyph(story.type),
          decodeWidth: 1080,
          glyphScale: 0.34,
        ),
        // Scrim so the footer copy stays readable over any artwork (§6.6).
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x9905030A), Color(0x00000000), Color(0xE605030A)],
              stops: [0.0, 0.35, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

/// Category, title, supporting copy and the single primary action.
/// One visible primary CTA per story — never competing buttons (§7.3, §26.5).
class _StoryFooter extends StatelessWidget {
  const _StoryFooter({
    required this.story,
    required this.ctaLabel,
    required this.onCta,
  });

  final DiscoverStory story;
  final String ctaLabel;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          story.category.toUpperCase(),
          style: WtmType.micro.copyWith(
            fontSize: 9,
            letterSpacing: 1.1,
            color: WtmColors.gold,
          ),
        ),
        const SizedBox(height: WtmSpace.s6),
        Text(
          story.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: WtmType.h1.copyWith(height: 1.15),
        ),
        if (story.subtitle != null) ...[
          const SizedBox(height: WtmSpace.s6),
          Text(
            story.subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: WtmType.body.copyWith(color: WtmColors.muted),
          ),
        ],
        const SizedBox(height: WtmSpace.s16),
        GradientCta(label: ctaLabel, onPressed: onCta),
      ],
    );
  }
}
