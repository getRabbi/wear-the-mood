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

String _img(String seed) => 'https://picsum.photos/seed/$seed/600/800';

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

/// Stand-in for "you" until avatar/selfie capture lands (§8).
final samplePersonImageUrl = _img('fashionos-you');
