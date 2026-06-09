import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/wardrobe_item.dart';

/// Placeholder closet contents until the wardrobe backend + image upload (§8)
/// land. Public images so tiles render; swap for `GET /v1/wardrobe` later.
const _sampleWardrobe = <WardrobeItem>[
  WardrobeItem(
    id: 'w1',
    title: 'White tee',
    category: 'Tops',
    imageUrl: 'https://picsum.photos/seed/fos-w-tee/600/800',
  ),
  WardrobeItem(
    id: 'w2',
    title: 'Black jeans',
    category: 'Bottoms',
    imageUrl: 'https://picsum.photos/seed/fos-w-jeans/600/800',
  ),
  WardrobeItem(
    id: 'w3',
    title: 'Leather boots',
    category: 'Shoes',
    imageUrl: 'https://picsum.photos/seed/fos-w-boots/600/800',
  ),
  WardrobeItem(
    id: 'w4',
    title: 'Wool coat',
    category: 'Outerwear',
    imageUrl: 'https://picsum.photos/seed/fos-w-coat/600/800',
  ),
  WardrobeItem(
    id: 'w5',
    title: 'Striped shirt',
    category: 'Tops',
    imageUrl: 'https://picsum.photos/seed/fos-w-stripe/600/800',
  ),
  WardrobeItem(
    id: 'w6',
    title: 'Canvas sneakers',
    category: 'Shoes',
    imageUrl: 'https://picsum.photos/seed/fos-w-sneak/600/800',
  ),
];

/// The user's wardrobe. Async so the screen wires loading/error/empty/content
/// (§4.3) now and needs no change when the real repository replaces this body.
final wardrobeItemsProvider = FutureProvider.autoDispose<List<WardrobeItem>>((
  ref,
) async {
  return _sampleWardrobe;
});
