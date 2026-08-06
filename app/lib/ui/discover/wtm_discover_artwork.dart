import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../shared/utils/image_format.dart';
import '../widgets/widgets.dart';

/// Test hook: the skeleton shown while a Discover image is in flight.
const wtmArtworkSkeletonKey = Key('wtm-artwork-skeleton');

/// Test hook: the drawn fallback used when there is no image, or it failed.
const wtmArtworkFallbackKey = Key('wtm-artwork-fallback');

/// Artwork for a Discover card: the real image where there is one, a subtle
/// skeleton while it loads, and a drawn fallback when there is not.
///
/// Three separate states on purpose. The surface previously used the same flat
/// aurora panel for all three, which meant a slow network, an absent image and
/// a dead CDN all looked identical — and on a catalog whose image host does not
/// resolve, every single card came out as the same blank violet rectangle.
///
/// The fallback is deterministic per [seed] and follows the approved
/// prototype's own treatment: the prototype gives each card a different
/// gradient and a garment silhouette, never an empty panel. So does this — the
/// same product always draws the same way, and two cards side by side never
/// look like a copy of each other.
class WtmDiscoverArtwork extends StatelessWidget {
  const WtmDiscoverArtwork({
    super.key,
    required this.url,
    required this.seed,
    this.glyph = WtmGlyph.hanger,
    this.decodeWidth = 500,
    this.alignment = Alignment.center,
    this.colorFilter,
    this.glyphScale = 0.42,
  });

  /// The image to show. Null or empty goes straight to the fallback — that is
  /// normal content, not an error, so it never waits on a skeleton first.
  final String? url;

  /// Stable identity — a product or story id. Picks which fallback variant this
  /// card wears, so the choice survives scrolling, refreshes and reinstalls.
  final String seed;

  /// Silhouette drawn on the fallback. Callers pass the garment glyph closest
  /// to the item's category.
  final WtmGlyph glyph;

  /// Decode size. A rail of full-resolution photos is the fastest way to make
  /// Discover stutter.
  final int decodeWidth;

  /// Focal point, so a portrait crop does not cut a face or a hemline.
  final Alignment alignment;

  /// Applied to the photograph only — a desaturated sold-out product should not
  /// also drain the drawn fallback, which carries no stock meaning.
  final ColorFilter? colorFilter;

  /// Silhouette size as a fraction of the shorter edge.
  final double glyphScale;

  /// The prototype's product-image variants: a coloured bloom over a deep
  /// diagonal base. Four, cycled by [seed], exactly as `.product-card:nth-child`
  /// does.
  static const _variants = <(Color, Color, Color)>[
    // `radial(rgba(237,151,223,.48)) over linear(145deg,#2b1748,#100b1c)`
    (Color(0x7AED97DF), Color(0xFF2B1748), Color(0xFF100B1C)),
    // teal / mint
    (Color(0x66A2E1CD), Color(0xFF17333A), Color(0xFF0B1119)),
    // amber / tobacco
    (Color(0x6BEDC68C), Color(0xFF48321D), Color(0xFF130D0A)),
    // violet
    (Color(0x73AC93FF), Color(0xFF2A2358), Color(0xFF0E0B19)),
  ];

  @override
  Widget build(BuildContext context) {
    final source = url?.trim() ?? '';
    if (source.isEmpty) return _fallback();

    final image = CachedNetworkImage(
      imageUrl: source,
      cacheKey: stableImageCacheKey(source),
      fit: BoxFit.cover,
      alignment: alignment,
      memCacheWidth: decodeWidth,
      // A quiet pulse, not a decorative panel: it has to read as "an image is
      // coming", which a finished-looking gradient never does.
      placeholder: (_, _) => _skeleton(),
      // A real failure lands on the same drawn card an image-less product gets.
      errorWidget: (_, _, _) => _fallback(),
    );

    return colorFilter == null
        ? image
        : ColorFiltered(colorFilter: colorFilter!, child: image);
  }

  Widget _skeleton() => const ColoredBox(
    key: wtmArtworkSkeletonKey,
    color: Color(0xFF16111F),
    child: LoadingShimmerFill(),
  );

  Widget _fallback() {
    final (bloom, top, bottom) = _variants[_variantFor(seed)];
    return DecoratedBox(
      key: wtmArtworkFallbackKey,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(-0.574, -0.819), // 145deg
          end: const Alignment(0.574, 0.819),
          colors: [top, bottom],
          stops: const [0.0, 0.72],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The bloom, high and slightly right, as every prototype card has it.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.3, -0.6),
                radius: 0.85,
                colors: [bloom, bloom.withAlpha(0)],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
          // The silhouette. Sized off the box rather than a constant, so it
          // stays right on a rail card and on a full-width feature card.
          LayoutBuilder(
            builder: (context, constraints) {
              final edge =
                  (constraints.hasBoundedWidth && constraints.hasBoundedHeight)
                  ? (constraints.maxWidth < constraints.maxHeight
                        ? constraints.maxWidth
                        : constraints.maxHeight)
                  : 96.0;
              return Center(
                child: WtmIcon(
                  glyph,
                  size: edge * glyphScale,
                  color: Colors.white.withValues(alpha: 0.30),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Stable, non-negative variant index. `hashCode` is stable within a run and
  /// the value only ever picks a colour, so a rehash across releases is
  /// harmless.
  static int _variantFor(String seed) =>
      seed.isEmpty ? 0 : seed.hashCode.abs() % _variants.length;
}

/// A shimmer that fills its parent — [LoadingShimmer] wants explicit sizes,
/// which a `Stack`-expanded slot cannot give it.
class LoadingShimmerFill extends StatefulWidget {
  const LoadingShimmerFill({super.key});

  @override
  State<LoadingShimmerFill> createState() => _LoadingShimmerFillState();
}

class _LoadingShimmerFillState extends State<LoadingShimmerFill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.30,
        end: 0.62,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF241C33), Color(0xFF171224)],
          ),
        ),
      ),
    );
  }
}

/// The garment silhouette closest to a catalog category.
///
/// Falls back to the hanger, which reads as "a piece of clothing" for anything
/// the catalog names in a way this does not recognise.
WtmGlyph wtmGarmentGlyph(String? category) {
  switch ((category ?? '').trim().toLowerCase()) {
    case 'tops':
    case 'top':
    case 'shirts':
    case 'tees':
      return WtmGlyph.shirt;
    case 'dresses':
    case 'dress':
    case 'outerwear':
    case 'jackets':
      return WtmGlyph.hanger;
    case 'accessories':
    case 'bags':
    case 'jewelry':
      return WtmGlyph.store;
    default:
      return WtmGlyph.hanger;
  }
}
