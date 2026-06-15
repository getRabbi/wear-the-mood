import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'loading_shimmer.dart';

/// Convenience skeletons (CLAUDE.md §4.3 loading state) built on the dependency-
/// free [LoadingShimmer]. Gives screens ready-made placeholder shapes so loading
/// states look designed, not like a bare spinner.
abstract final class SkeletonLoader {
  /// A pulsing rounded box (image/tile placeholder).
  static Widget box({double? width, double height = 120, double radius = AppRadius.card}) =>
      LoadingShimmer(
        width: width,
        height: height,
        borderRadius: BorderRadius.circular(radius),
      );

  /// A short text line.
  static Widget line({double width = 120, double height = 12}) => LoadingShimmer(
    width: width,
    height: height,
    borderRadius: BorderRadius.circular(AppRadius.sm),
  );

  /// A 2-column grid of tile placeholders for closet/picker screens.
  static Widget grid({int count = 6, double aspectRatio = 0.72}) =>
      GridView.builder(
        padding: const EdgeInsets.all(AppSpace.lg),
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: AppSpace.md,
          crossAxisSpacing: AppSpace.md,
          childAspectRatio: aspectRatio,
        ),
        itemCount: count,
        itemBuilder: (_, _) => box(width: double.infinity, height: double.infinity),
      );

  /// A horizontal row of tile placeholders (Home previews).
  static Widget rowTiles({
    double height = 150,
    double width = 120,
    int count = 6,
  }) => SizedBox(
    height: height,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
      itemBuilder: (_, _) => box(width: width, height: height),
    ),
  );
}
