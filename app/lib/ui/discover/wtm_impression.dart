import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../features/discover/application/discover_providers.dart';

/// Counts an impression for [impressionKey] once it has genuinely been looked
/// at (DISCOVER spec §22).
///
/// "Genuinely" is three rules, and all three matter:
///
///  * **At least [minVisibleFraction] visible.** A sliver of a card peeking in
///    at the fold is not an impression.
///  * **For at least [minDwell].** A fast scroll past a card is not an
///    impression either, so the timer starts when the card becomes visible and
///    is cancelled the moment it stops being visible. Only surviving the full
///    dwell fires [onImpression].
///  * **Once per key per session.** Deduplicated through
///    [discoverImpressionsProvider], which lives in memory and dies with the
///    app — so scrolling a card off and back does not re-count it, and a fresh
///    launch is a fresh session.
///
/// Inflating impressions would quietly corrupt every rate the rollout is
/// judged on (story open rate, save rate, click-through), which is why the
/// rules live in one widget instead of at each call site.
class WtmImpression extends ConsumerStatefulWidget {
  const WtmImpression({
    super.key,
    required this.impressionKey,
    required this.onImpression,
    required this.child,
    this.minVisibleFraction = 0.5,
    this.minDwell = const Duration(milliseconds: 500),
  });

  /// Stable identity for what is being seen, e.g. `story:giveaway-hub`.
  /// Also the deduplication key, so it must not change between rebuilds of the
  /// same content.
  final String impressionKey;

  /// Fired at most once per key per session, after the dwell completes.
  final VoidCallback onImpression;

  final Widget child;
  final double minVisibleFraction;
  final Duration minDwell;

  @override
  ConsumerState<WtmImpression> createState() => _WtmImpressionState();
}

class _WtmImpressionState extends ConsumerState<WtmImpression> {
  Timer? _dwell;
  bool _fired = false;

  @override
  void dispose() {
    _dwell?.cancel();
    super.dispose();
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (_fired || !mounted) return;

    if (info.visibleFraction < widget.minVisibleFraction) {
      // Left the threshold before the dwell completed — that was a scroll-past,
      // not a view. Start again from zero next time.
      _dwell?.cancel();
      _dwell = null;
      return;
    }

    if (_dwell != null) return; // already counting down
    _dwell = Timer(widget.minDwell, () {
      if (!mounted || _fired) return;
      // The session-wide guard has the final say: another instance of the same
      // card (a rebuild, or the same story in two places) must not double-count.
      if (!ref
          .read(discoverImpressionsProvider.notifier)
          .register(widget.impressionKey)) {
        _fired = true; // someone else already counted it; stop watching
        return;
      }
      _fired = true;
      widget.onImpression();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Once fired there is nothing left to observe, so the detector is dropped
    // entirely rather than left running for the life of the screen.
    if (_fired) return widget.child;
    return VisibilityDetector(
      key: Key('impression:${widget.impressionKey}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: widget.child,
    );
  }
}
