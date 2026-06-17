import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/outfit.dart';
import '../../data/models/wardrobe_item.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../wardrobe/wardrobe_providers.dart';

/// Resolves an outfit's piece images (cutouts) from the loaded closet, in the
/// outfit's saved order. Falls back to the cover image when items aren't loaded.
List<String> outfitImageUrls(Outfit outfit, List<WardrobeItem> closet) {
  final byId = {for (final i in closet) i.id: i};
  final urls = <String>[
    for (final id in outfit.itemIds) ?byId[id]?.displayImageUrl,
  ];
  if (urls.isEmpty && (outfit.coverImageUrl?.isNotEmpty ?? false)) {
    urls.add(outfit.coverImageUrl!);
  }
  return urls;
}

/// An outfit grid card — a clean editorial flat-lay of its pieces (§5.2). A thin
/// wrapper that resolves the outfit's images from the loaded closet and hands
/// them to the shared [OutfitCard]. Behavior unchanged; only the look.
class OutfitCollageCard extends ConsumerWidget {
  const OutfitCollageCard({
    super.key,
    required this.outfit,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
    this.onLongPress,
  });

  final Outfit outfit;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final closet = ref.watch(wardrobeItemsProvider).asData?.value ?? const [];
    final name = (outfit.name?.trim().isNotEmpty ?? false)
        ? outfit.name!.trim()
        : l10n.outfitsUntitled;

    return OutfitCard(
      imageUrls: outfitImageUrls(outfit, closet),
      name: name,
      count: outfit.itemCount,
      isFavorite: isFavorite,
      onTap: onTap,
      onToggleFavorite: onToggleFavorite,
      onLongPress: onLongPress,
    );
  }
}
