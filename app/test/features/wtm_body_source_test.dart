import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/studio_model_preset.dart';
import 'package:app/data/models/tryon_photo.dart';
import 'package:app/ui/mirror/wtm_body_source.dart';

/// Mobile QA #1/#2: the ONE body the user picks in MoodMirror Step 1 must be the
/// exact body every downstream step (Step 2/3, 2D editor, AI job) renders. These
/// pin the pure resolution the whole flow shares — no silent default swap, and a
/// clear "reselect" signal when the selected source can't be resolved.

const _selected = TryonPhoto(
  id: 'p1',
  storagePath: 'avatars/u/p1.jpg',
  signedUrl: 'https://cdn.test/p1.png',
  isSelected: true,
);

const _other = TryonPhoto(
  id: 'p0',
  storagePath: 'avatars/u/p0.jpg',
  signedUrl: 'https://cdn.test/p0.png',
);

void main() {
  group('selectedTryonPhoto', () {
    test('prefers the explicitly selected photo', () {
      expect(selectedTryonPhoto(const [_other, _selected])?.id, 'p1');
    });

    test('falls back to the first (newest) when none is selected', () {
      expect(
        selectedTryonPhoto(const [
          TryonPhoto(id: 'a', storagePath: 'x', signedUrl: 'u/a'),
          TryonPhoto(id: 'b', storagePath: 'x', signedUrl: 'u/b'),
        ])?.id,
        'a',
      );
    });

    test('is null on an empty gallery', () {
      expect(selectedTryonPhoto(const []), isNull);
    });
  });

  group('resolveWtmBodyFrom', () {
    test('my photo resolves to the SELECTED gallery photo (Step 1 == render)', () {
      final r = resolveWtmBodyFrom(const WtmBodyPhoto(), const [_other, _selected]);
      expect(r, isA<WtmBodyResolvedImage>());
      final img = r as WtmBodyResolvedImage;
      expect(img.url, 'https://cdn.test/p1.png');
      expect(img.kind, WtmBodyKind.photo);
      expect(img.sourceId, 'p1');
    });

    test('my photo with an empty gallery → none (activation path)', () {
      expect(
        resolveWtmBodyFrom(const WtmBodyPhoto(), const []),
        isA<WtmBodyResolvedNone>(),
      );
    });

    test('my photo whose selected shot has no URL → unavailable, not a default', () {
      const noUrl = TryonPhoto(
        id: 'p2',
        storagePath: 'avatars/u/p2.jpg',
        isSelected: true,
      );
      expect(
        resolveWtmBodyFrom(const WtmBodyPhoto(), const [noUrl]),
        isA<WtmBodyResolvedUnavailable>(),
      );
    });

    test('studio model resolves to the model image', () {
      const model = StudioModelPreset(
        id: 'm1',
        name: 'Runway Ava',
        imageUrl: 'https://cdn.test/model.png',
      );
      final r = resolveWtmBodyFrom(const WtmBodyModel(model), const [_selected]);
      expect(r, isA<WtmBodyResolvedImage>());
      final img = r as WtmBodyResolvedImage;
      expect(img.url, 'https://cdn.test/model.png');
      expect(img.kind, WtmBodyKind.model);
      expect(img.sourceId, 'm1');
    });

    test('a model with no image → unavailable', () {
      const model = StudioModelPreset(id: 'm2', name: 'Soon');
      expect(
        resolveWtmBodyFrom(const WtmBodyModel(model), const []),
        isA<WtmBodyResolvedUnavailable>(),
      );
    });

    test('mannequin resolves to the mannequin', () {
      expect(
        resolveWtmBodyFrom(const WtmBodyMannequin(), const [_selected]),
        isA<WtmBodyResolvedMannequin>(),
      );
    });
  });
}
