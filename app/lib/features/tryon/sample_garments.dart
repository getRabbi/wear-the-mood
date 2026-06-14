/// Placeholder garment catalog + stand-in person photo.
///
/// These let the try-on loop be demoed end-to-end against the backend stub
/// before the real wardrobe and image upload (CLAUDE.md §8) land. The URLs are
/// stable public images the backend can fetch; swap them for real wardrobe
/// items / a captured selfie once §8 ships.
class SampleGarment {
  const SampleGarment({
    required this.id,
    required this.name,
    required this.imageUrl,
  });

  final String id;
  final String name;
  final String imageUrl;
}

const sampleGarments = <SampleGarment>[
  SampleGarment(
    id: 'g1',
    name: 'Linen shirt',
    imageUrl: 'https://picsum.photos/seed/fos-linen/600/800',
  ),
  SampleGarment(
    id: 'g2',
    name: 'Denim jacket',
    imageUrl: 'https://picsum.photos/seed/fos-denim/600/800',
  ),
  SampleGarment(
    id: 'g3',
    name: 'Knit sweater',
    imageUrl: 'https://picsum.photos/seed/fos-knit/600/800',
  ),
  SampleGarment(
    id: 'g4',
    name: 'Trench coat',
    imageUrl: 'https://picsum.photos/seed/fos-trench/600/800',
  ),
  SampleGarment(
    id: 'g5',
    name: 'Summer dress',
    imageUrl: 'https://picsum.photos/seed/fos-dress/600/800',
  ),
  SampleGarment(
    id: 'g6',
    name: 'Tailored blazer',
    imageUrl: 'https://picsum.photos/seed/fos-blazer/600/800',
  ),
];

/// Curated, stable full-body **fashion** looks (Unsplash, free license). Unlike
/// the random `picsum` seeds above, these are real model shots — used for the
/// home hero carousel and the avatar guide's "good example". Swap freely for
/// owned/branded imagery later.
const sampleLookImageUrls = <String>[
  'https://images.unsplash.com/photo-1539109136881-3be0616acf4b?w=800&q=80&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1488161628813-04466f872be2?w=800&q=80&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1483985988355-763728e1935b?w=800&q=80&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1490481651871-ab68de25d43d?w=800&q=80&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1529139574466-a303027c1d8b?w=800&q=80&fit=crop&auto=format',
];

/// Stand-in for "you" until avatar/selfie capture lands (§8) + the avatar guide's
/// "good example" full-body shot.
final samplePersonImageUrl = sampleLookImageUrls.first;
