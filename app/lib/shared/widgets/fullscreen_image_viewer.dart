import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Opens a full-screen, pinch-to-zoom photo viewer over the current screen
/// (CLAUDE.md §4.3 — images are the hero). Default feed/profile tiles stay as
/// cards; the full-screen view appears only on tap. No extra dependency — built
/// on [InteractiveViewer] + [Hero].
Future<void> showFullscreenImage(
  BuildContext context,
  String imageUrl, {
  Object? heroTag,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: AppMotion.base,
      pageBuilder: (_, _, _) =>
          _FullscreenImage(imageUrl: imageUrl, heroTag: heroTag),
    ),
  );
}

class _FullscreenImage extends StatelessWidget {
  const _FullscreenImage({required this.imageUrl, this.heroTag});

  final String imageUrl;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final image = CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.contain,
      fadeInDuration: AppMotion.fast,
      placeholder: (_, _) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
      errorWidget: (_, _, _) =>
          const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Tap anywhere (outside the pinch area) to dismiss.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: heroTag != null
                  ? Hero(tag: heroTag!, child: image)
                  : image,
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + AppSpace.sm,
            right: AppSpace.sm,
            child: Material(
              color: AppColors.scrim,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
