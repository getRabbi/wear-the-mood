import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/studio_model_preset.dart';
import '../../features/profile/avatar_service.dart';

/// The "try-on body" the user picked in the Body & Try-On page (Fix 5). The
/// default is their own selected try-on photo; they can instead pick a studio
/// model or the bundled mannequin. Session-local (no backend) and kept across
/// step navigation so MoodMirror Step 1 + the render both honour the choice.
sealed class WtmBodyChoice {
  const WtmBodyChoice();
}

/// Use the user's own selected try-on photo (the default).
class WtmBodyPhoto extends WtmBodyChoice {
  const WtmBodyPhoto();
}

/// Try clothes on a curated studio model instead of a personal photo.
class WtmBodyModel extends WtmBodyChoice {
  const WtmBodyModel(this.model);

  final StudioModelPreset model;
}

/// The bundled procedural mannequin — always available, no photo, 2D preview.
class WtmBodyMannequin extends WtmBodyChoice {
  const WtmBodyMannequin();
}

class WtmBodyChoiceNotifier extends Notifier<WtmBodyChoice> {
  @override
  WtmBodyChoice build() => const WtmBodyPhoto();

  void usePhoto() => state = const WtmBodyPhoto();
  void useModel(StudioModelPreset model) => state = WtmBodyModel(model);
  void useMannequin() => state = const WtmBodyMannequin();
}

/// The active body choice for MoodMirror.
final wtmBodyChoiceProvider =
    NotifierProvider<WtmBodyChoiceNotifier, WtmBodyChoice>(
        WtmBodyChoiceNotifier.new);

/// Resolved body for MoodMirror: the image URL to render/generate on and whether
/// it's the procedural mannequin (no URL). For "my photo" it falls back to the
/// user's selected try-on photo signed URL.
typedef WtmBodyImage = ({String? url, bool mannequin});

final wtmBodyImageProvider = Provider<WtmBodyImage>((ref) {
  final choice = ref.watch(wtmBodyChoiceProvider);
  return switch (choice) {
    WtmBodyModel(:final model) => (url: model.imageUrl, mannequin: false),
    WtmBodyMannequin() => (url: null, mannequin: true),
    WtmBodyPhoto() => (
        url: ref.watch(avatarSignedUrlProvider).asData?.value,
        mannequin: false,
      ),
  };
});
