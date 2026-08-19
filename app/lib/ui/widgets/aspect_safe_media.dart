import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The ONE way Wear The Mood presents a photograph whose real proportions matter
/// — a body reference, a garment, a try-on render.
///
/// ## The defect this exists to remove
///
/// Every one of those surfaces used to hand its photo a container of a size the
/// SCREEN chose, and then asked `BoxFit` to reconcile the two. That produces one
/// of exactly two wrong pictures, and the app shipped both:
///
///  * `BoxFit.contain` in a fixed, near-square box. MoodMirror step 1 drew its
///    arch at a hard `height: 322` across a ~320dp column, so a perfectly
///    ordinary 9:16 phone photo was letterboxed down to a ~170dp-wide ribbon
///    with dead space either side. Nothing was stretched — and it still read as
///    "my photo has gone long and thin", because a portrait subject in a square
///    hole is a ribbon no matter how correct the pixels are.
///  * `BoxFit.cover` in the same fixed box. The opposite failure: the photo
///    fills the frame by having its top and bottom thrown away, which on a
///    full-body reference means the head and the feet — the two things the
///    screen exists to let someone check.
///
/// ## The rule
///
/// The BOX takes its shape from the IMAGE, not the other way round. Once the
/// container already has the photo's proportions there is nothing left for a fit
/// to reconcile: the image fills its width completely, and `contain` becomes a
/// no-op rather than a crop or a ribbon.
///
/// Bounds keep that from destabilising a scrollable screen: a source ratio is
/// clamped into [minAspectRatio] … [maxAspectRatio] and the resulting height into
/// [minHeight] … [maxHeight]. Only when a clamp actually bites does any
/// letterboxing appear, and it is bounded by construction — an 8:1 panorama
/// cannot produce a 40dp sliver and a 1:4 crop cannot produce a 1200dp tower.
///
/// The image is drawn with `BoxFit.contain` in every case, so this widget can
/// never stretch and can never crop. That is the whole contract.
///
/// ## What it does NOT do
///
/// It does not restyle anything. Callers keep their own frame, radius, aurora
/// ground, shimmer and error faces; this decides a box and nothing else, which
/// is why it can be dropped into MoodMirror, Add Garment and the result screen
/// without touching their visual language.
class AspectSafeMedia extends StatefulWidget {
  const AspectSafeMedia({
    super.key,
    required this.image,
    required this.child,
    this.fallbackAspectRatio = defaultFallbackAspectRatio,
    this.minAspectRatio = defaultMinAspectRatio,
    this.maxAspectRatio = defaultMaxAspectRatio,
    this.minHeight,
    this.maxHeight,
    this.background,
    this.padding = EdgeInsets.zero,
  });

  /// The provider whose INTRINSIC size decides the box.
  ///
  /// Resolved through the ordinary [ImageCache], so probing it here and painting
  /// it in [child] is one decode and — for a network image sharing a cache key —
  /// one download.
  final ImageProvider image;

  /// What actually paints. Must use `BoxFit.contain`; the box is already the
  /// right shape, so any other fit would re-introduce the crop this removes.
  final Widget child;

  /// Shape assumed until the real one is known.
  ///
  /// Portrait, because every surface using this widget shows a standing person
  /// or a hanging garment. Getting it close matters only for one frame, but a
  /// wildly wrong guess is a visible jump on a slow connection.
  final double fallbackAspectRatio;

  /// Narrowest (tallest) box this widget will build, as width/height.
  final double minAspectRatio;

  /// Widest (shortest) box this widget will build, as width/height.
  final double maxAspectRatio;

  /// Absolute height bounds in logical pixels, applied AFTER the ratio clamp.
  /// A screen that must fit other content below the image passes [maxHeight].
  final double? minHeight;
  final double? maxHeight;

  /// Painted behind [child] and sized to the full box, so the letterboxed strip
  /// left by a clamp is the surface's own ground rather than a bare rectangle.
  final Widget? background;

  /// A decorative inset between the frame and the media — the arch's inner
  /// margin, for instance.
  ///
  /// Taken off the width BEFORE the height is derived, and added back onto the
  /// outside afterwards, so the media area itself still lands on the source
  /// ratio. Ignoring it would leave a thin permanent letterbox on every photo,
  /// which is the same defect in miniature.
  /// Height bounds apply to the MEDIA area, not to the padded outside, so a
  /// caller reasons about the picture rather than about its frame.
  final EdgeInsets padding;

  /// A 3:4 standing portrait — what a closet photo and a body shot usually are.
  static const defaultFallbackAspectRatio = 3 / 4;

  /// 9:16. Taller than a full-screen phone photo is a panorama on its side or a
  /// stitched screenshot, and neither should be allowed to own a whole screen.
  static const defaultMinAspectRatio = 9 / 16;

  /// 16:9. Wider than this is a banner, not a garment or a person.
  static const defaultMaxAspectRatio = 16 / 9;

  @override
  State<AspectSafeMedia> createState() => _AspectSafeMediaState();
}

class _AspectSafeMediaState extends State<AspectSafeMedia> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _sourceAspectRatio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
  }

  @override
  void didUpdateWidget(AspectSafeMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      // A different photo is a different shape. Drop the old one's ratio rather
      // than laying the new image out in the previous one's box for a frame.
      _sourceAspectRatio = null;
      _subscribe();
    }
  }

  void _subscribe() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key && _listener != null) return;
    _unsubscribe();
    final listener = ImageStreamListener(
      _onImage,
      // A failed probe is not an error state: [child] owns error messaging, and
      // the box simply stays on the fallback shape so the surface keeps its
      // rhythm instead of collapsing to nothing.
      onError: (_, _) {},
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _unsubscribe() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  void _onImage(ImageInfo info, bool synchronous) {
    final ratio = info.image.width / info.image.height;
    // Release the decoded handle immediately — the ratio is all this needs, and
    // `child` holds its own reference for painting.
    info.dispose();
    if (!ratio.isFinite || ratio <= 0) return;
    if (_sourceAspectRatio == ratio) return;
    if (synchronous) {
      // Already inside a build/layout pass (a warm cache hit resolves inline);
      // assigning without setState is both legal and required here.
      _sourceAspectRatio = ratio;
      return;
    }
    if (!mounted) return;
    setState(() => _sourceAspectRatio = ratio);
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Unbounded width has no box to derive a height from. Every caller sits
        // in a bounded column, so this is a safety net rather than a path: fall
        // back to the viewport so the widget degrades to "sensible" instead of
        // to an infinity assertion.
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final padding = widget.padding;
        final media = aspectSafeBoxSize(
          width: math.max(0, width - padding.horizontal),
          sourceAspectRatio: _sourceAspectRatio ?? widget.fallbackAspectRatio,
          minAspectRatio: widget.minAspectRatio,
          maxAspectRatio: widget.maxAspectRatio,
          minHeight: widget.minHeight,
          maxHeight: widget.maxHeight,
        );
        final background = widget.background;
        final content = padding == EdgeInsets.zero
            ? widget.child
            : Padding(padding: padding, child: widget.child);
        return SizedBox(
          width: width,
          height: media.height + padding.vertical,
          child: background == null
              ? content
              : Stack(fit: StackFit.expand, children: [background, content]),
        );
      },
    );
  }
}

/// The box [AspectSafeMedia] draws, as a pure function of the source shape and
/// the bounds.
///
/// Split out so the geometry — the part a regression can actually be written
/// against — is testable without pumping a widget or decoding a real image.
///
/// Guarantees, in order of application:
///
/// 1. the box ratio is the SOURCE ratio, clamped into
///    [minAspectRatio] … [maxAspectRatio];
/// 2. height follows from width and that ratio — the second dimension is always
///    DERIVED, never independently chosen;
/// 3. height is then clamped into [minHeight] … [maxHeight].
///
/// Because the caller paints with `BoxFit.contain`, steps 1 and 3 can only ever
/// add symmetric letterboxing. Neither can distort the subject.
@visibleForTesting
Size aspectSafeBoxSize({
  required double width,
  required double sourceAspectRatio,
  double minAspectRatio = AspectSafeMedia.defaultMinAspectRatio,
  double maxAspectRatio = AspectSafeMedia.defaultMaxAspectRatio,
  double? minHeight,
  double? maxHeight,
}) {
  if (width <= 0 || !width.isFinite) return Size.zero;
  final ratio = sourceAspectRatio.isFinite && sourceAspectRatio > 0
      ? sourceAspectRatio
      : AspectSafeMedia.defaultFallbackAspectRatio;
  // A caller that passes the bounds the wrong way round gets a usable box rather
  // than a NaN: clamp() asserts on an inverted range.
  final low = minAspectRatio <= maxAspectRatio
      ? minAspectRatio
      : maxAspectRatio;
  final high = minAspectRatio <= maxAspectRatio
      ? maxAspectRatio
      : minAspectRatio;
  final boxRatio = ratio.clamp(low, high);
  var height = width / boxRatio;
  if (minHeight != null && height < minHeight) height = minHeight;
  if (maxHeight != null && height > maxHeight) height = maxHeight;
  return Size(width, height);
}

/// How much of [box] a `BoxFit.contain` render of [source] actually paints.
///
/// The acceptance number for Issue 1: "does a normal portrait photo use a real
/// share of the width, or a ribbon down the middle". Exposed so a widget test
/// can assert the drawn rectangle rather than eyeballing a golden.
@visibleForTesting
Size containedMediaSize({required Size box, required Size source}) {
  if (box.isEmpty || source.isEmpty) return Size.zero;
  final scale = math.min(box.width / source.width, box.height / source.height);
  return Size(source.width * scale, source.height * scale);
}
