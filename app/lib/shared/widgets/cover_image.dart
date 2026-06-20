import 'package:flutter/material.dart';

import '../../core/branding/category_covers.dart';

/// Renders a curated category/slot cover image for [coverKey] when one is
/// available, otherwise the caller's [fallback] (CATEGORY_COVER_IMAGES.md).
///
/// Covers are decorative category art / empty-slot placeholders — never a claim
/// the user owns that exact item. When covers are disabled, the key is unmapped,
/// or the asset is missing, the fallback is shown silently (no thrown error /
/// Sentry spam), so this ships before any image exists and upgrades the instant
/// the assets land + [kCoverImagesEnabled] flips.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.coverKey,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  /// Lookup key into [coverAsset] (e.g. `'tops'`, `'slot_shoes'`).
  final String coverKey;

  /// Built when no cover image is available — keeps the existing look.
  final WidgetBuilder fallback;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final asset = coverAsset(coverKey);
    if (asset == null) return fallback(context);
    return Image.asset(
      asset,
      fit: fit,
      // Decorative — the surrounding label carries the meaning.
      excludeFromSemantics: true,
      // Belt-and-suspenders: a registered-but-missing file falls back too.
      errorBuilder: (context, _, _) => fallback(context),
    );
  }
}
