/// How a remote AI operation is classified for privacy purposes.
///
/// The point of a typed classification rather than a `bool needsConsent` at each
/// call site is that adding a feature forces a decision. A new AI surface cannot
/// be written without naming which of these it is, and the two non-personal
/// values are the ones a reviewer can check against the data path rather than
/// against a screen's marketing name.
enum AiInputPrivacy {
  /// Runs entirely on the device. Nothing is uploaded, no provider is called.
  /// The free 2D preview and on-device background removal are this.
  localOnly,

  /// Leaves the app, but carries no personal imagery — a curated Wear The Mood
  /// studio model, a catalog product photo, or a garment the user photographed
  /// on its own. No consent sheet: asking permission to share a picture of a
  /// shirt is friction that teaches people to dismiss the prompt that matters.
  nonPersonalProductImage,

  /// Sends an image the user provided of THEMSELVES to a third-party AI
  /// provider. Requires current, explicit consent before anything is
  /// transmitted and before any credit is committed.
  personalImage;

  /// Whether this classification must pass the consent gate.
  bool get requiresPersonalImageConsent => this == AiInputPrivacy.personalImage;
}
