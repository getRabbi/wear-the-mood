import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/studio_model_preset.dart';
import '../../data/models/tryon_photo.dart';
import '../../data/repositories/tryon_photos_repository.dart';

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

/// The gallery's active try-on photo: the explicitly-selected one, else the most
/// recent (first). Shared by MoodMirror Step 1's preview and [resolveWtmBody] at
/// submit so what the user SEES in Step 1 is exactly what renders (mobile QA #1).
TryonPhoto? selectedTryonPhoto(List<TryonPhoto> photos) {
  if (photos.isEmpty) return null;
  for (final p in photos) {
    if (p.isSelected) return p;
  }
  return photos.first;
}

/// The provenance of a resolved image body — for the debug QA logs.
enum WtmBodyKind { photo, model }

/// What the chosen body actually resolves to, ready to hand to an engine. One
/// resolver ([resolveWtmBody]) produces this for BOTH the 2D editor and the AI
/// job, so Step 1's choice is the body every downstream step uses (mobile QA #1).
sealed class WtmResolvedBody {
  const WtmResolvedBody();
}

/// A concrete image to render/generate on — the user's selected try-on photo or a
/// studio model. [kind] + [sourceId] are for provenance + the debug logs.
class WtmBodyResolvedImage extends WtmResolvedBody {
  const WtmBodyResolvedImage(this.url, {required this.kind, this.sourceId});

  final String url;
  final WtmBodyKind kind;
  final String? sourceId;
}

/// The procedural mannequin — the free 2D path only (there is no photo to send to
/// the AI renderer).
class WtmBodyResolvedMannequin extends WtmResolvedBody {
  const WtmBodyResolvedMannequin();
}

/// The user HAS a selected photo/model source, but it can't be resolved right now
/// — missing / expired / failed to load. The caller must ask them to reselect;
/// it must NEVER silently fall back to a stranger or an old default (mobile QA #1).
class WtmBodyResolvedUnavailable extends WtmResolvedBody {
  const WtmBodyResolvedUnavailable();
}

/// No body source at all (empty gallery, no model/mannequin picked). ONLY here may
/// the activation path substitute a sample stand-in.
class WtmBodyResolvedNone extends WtmResolvedBody {
  const WtmBodyResolvedNone();
}

/// Resolve the active [wtmBodyChoiceProvider] to a concrete body. The photo gallery
/// is AWAITED (`.future`), never bare-read — the same autoDispose-FutureProvider
/// footgun that silently mis-fired credit gating would otherwise hand back `null`
/// mid-navigation and drop the render onto the sample body. Used at submit by
/// MoodMirror Step 3 for both the 2D editor and the AI job.
Future<WtmResolvedBody> resolveWtmBody(WidgetRef ref) async {
  final choice = ref.read(wtmBodyChoiceProvider);
  // Model / mannequin don't touch the gallery.
  if (choice is! WtmBodyPhoto) return resolveWtmBodyFrom(choice, const []);
  try {
    final photos = await ref.read(tryonPhotosProvider.future);
    return resolveWtmBodyFrom(choice, photos);
  } catch (_) {
    // Couldn't load the gallery → ask to reselect rather than rendering a random
    // default.
    return const WtmBodyResolvedUnavailable();
  }
}

/// The pure core of [resolveWtmBody] (unit-testable): maps a [choice] — plus the
/// already-loaded [photos] for the "my photo" case — to a concrete body. Keeps
/// the single source of truth for what Step 1 previews and every engine renders.
WtmResolvedBody resolveWtmBodyFrom(
    WtmBodyChoice choice, List<TryonPhoto> photos) {
  switch (choice) {
    case WtmBodyModel(:final model):
      final url = model.imageUrl;
      if (url == null || url.isEmpty) return const WtmBodyResolvedUnavailable();
      return WtmBodyResolvedImage(url,
          kind: WtmBodyKind.model, sourceId: model.id);
    case WtmBodyMannequin():
      return const WtmBodyResolvedMannequin();
    case WtmBodyPhoto():
      if (photos.isEmpty) return const WtmBodyResolvedNone();
      final selected = selectedTryonPhoto(photos);
      final url = selected?.signedUrl;
      if (selected == null || url == null || url.isEmpty) {
        // The user has photos but the selected one has no usable URL (expired /
        // missing) — reselect, don't silently swap.
        return const WtmBodyResolvedUnavailable();
      }
      return WtmBodyResolvedImage(url,
          kind: WtmBodyKind.photo, sourceId: selected.id);
  }
}

/// A debug-only one-liner (id / url / type) for the QA logs requested at Step 1,
/// Step 3 submit, 2D-editor open, and AI job submit.
String describeWtmBody(WtmResolvedBody body) => switch (body) {
      WtmBodyResolvedImage(:final url, :final kind, :final sourceId) =>
        'image(kind=${kind.name}, id=$sourceId, url=$url)',
      WtmBodyResolvedMannequin() => 'mannequin',
      WtmBodyResolvedUnavailable() =>
        'unavailable(selected source missing/expired)',
      WtmBodyResolvedNone() => 'none(no body source)',
    };

/// Emit a `[MoodMirror] <stage> → <body>` line in debug builds only.
void debugLogWtmBody(String stage, WtmResolvedBody body) {
  if (kDebugMode) debugPrint('[MoodMirror] $stage → ${describeWtmBody(body)}');
}
