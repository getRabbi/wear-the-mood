/// Where the try-on body comes from (Try-On Body System — BUILD_PROMPT_PRO_PROMAX
/// .md). `myPhoto` maps to the backend `own_photo` (unchanged); `studioModel` maps
/// to `studio_model` (Pro/Pro Max, server-resolved preset). `user_avatar` / My
/// Style Model is future-ready only and intentionally NOT a value here yet.
enum TryOnBodySource {
  myPhoto,
  studioModel;

  /// The backend `model_source` value for this body source.
  String get apiValue =>
      this == TryOnBodySource.studioModel ? 'studio_model' : 'own_photo';
}
