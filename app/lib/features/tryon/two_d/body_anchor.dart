import 'dart:math' as math;
import 'dart:ui';

/// Normalized body landmarks (each point is a fraction 0..1 of the source image's
/// width/height) from on-device pose detection. Pure data — no ML Kit import — so
/// the placement math below is unit-testable. Any field may be null (not detected).
class BodyPose {
  const BodyPose({
    this.leftShoulder,
    this.rightShoulder,
    this.leftHip,
    this.rightHip,
    this.leftKnee,
    this.rightKnee,
    this.leftAnkle,
    this.rightAnkle,
    this.nose,
  });

  final Offset? leftShoulder;
  final Offset? rightShoulder;
  final Offset? leftHip;
  final Offset? rightHip;
  final Offset? leftKnee;
  final Offset? rightKnee;
  final Offset? leftAnkle;
  final Offset? rightAnkle;
  final Offset? nose;

  static Offset? _mid(Offset? a, Offset? b) =>
      (a != null && b != null) ? Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2) : null;

  Offset? get shoulderCenter => _mid(leftShoulder, rightShoulder);
  Offset? get hipCenter => _mid(leftHip, rightHip);
  Offset? get kneeCenter => _mid(leftKnee, rightKnee);
  Offset? get ankleCenter => _mid(leftAnkle, rightAnkle);

  double? get shoulderSpan => (leftShoulder != null && rightShoulder != null)
      ? (leftShoulder! - rightShoulder!).distance
      : null;
  double? get hipSpan =>
      (leftHip != null && rightHip != null) ? (leftHip! - rightHip!).distance : null;

  /// Shoulder-line lean (radians, ~0 when level) — drives the garment tilt.
  double get tilt {
    final l = leftShoulder, r = rightShoulder;
    if (l == null || r == null) return 0;
    final d = r - l;
    return math.atan2(d.dy, d.dx);
  }

  bool get hasTorso => shoulderCenter != null && hipCenter != null;
}

/// A garment's auto-placement in IMAGE space: width as a fraction of the image
/// width, the garment's vertical centre as a fraction of image height, and a
/// tilt (radians) to follow the body's lean.
class AnchoredPlacement {
  const AnchoredPlacement({
    required this.widthFactor,
    required this.verticalCenter,
    required this.tilt,
  });

  final double widthFactor;
  final double verticalCenter;
  final double tilt;
}

double _clampW(double w) => w.clamp(0.18, 0.98);
double _clamp01(double v) => v.clamp(0.0, 1.0);

/// Body-anchored placement for a garment from real landmarks, in IMAGE space.
/// Returns null when the needed landmarks are missing or the category is an
/// accessory (those keep the category heuristic, which handles them well) — the
/// caller then falls back to [garmentPlacement].
AnchoredPlacement? anchoredPlacement(String? category, BodyPose pose) {
  final c = (category ?? '').toLowerCase();
  bool has(List<String> keys) => keys.any(c.contains);

  // Accessories → keep the heuristic (head/hand/feet anchoring isn't reliable
  // from torso landmarks). Checked first so a "scarf" isn't treated as a top.
  if (has(const [
    'glass', 'sunglass', 'eyewear', 'hat', 'beanie', 'cap', 'headband',
    'turban', 'hijab', 'scarf', 'shawl', 'veil', 'earring', 'necklace',
    'pendant', 'choker', 'chain', 'watch', 'bracelet', 'wristband', 'cuff',
    'belt', 'bag', 'purse', 'tote', 'clutch', 'backpack', 'satchel',
  ])) {
    return null;
  }

  final sc = pose.shoulderCenter;
  final hc = pose.hipCenter;
  final kc = pose.kneeCenter;
  final ac = pose.ankleCenter;
  final ss = pose.shoulderSpan;
  final hs = pose.hipSpan;
  final tilt = pose.tilt;

  // Dress / one-piece: shoulders → knees (or hips).
  if (has(const ['dress', 'gown', 'jumpsuit', 'romper'])) {
    final lower = kc ?? hc;
    if (sc == null || lower == null || ss == null) return null;
    return AnchoredPlacement(
      widthFactor: _clampW(ss * 2.0),
      verticalCenter: _clamp01((sc.dy + lower.dy) / 2),
      tilt: tilt * 0.6,
    );
  }

  // Outerwear: shoulders → hips, a touch wider.
  if (has(const [
    'jacket', 'coat', 'blazer', 'outer', 'trench', 'parka', 'puffer',
    'vest', 'cardigan', 'hoodie',
  ])) {
    if (sc == null || hc == null || ss == null) return null;
    return AnchoredPlacement(
      widthFactor: _clampW(ss * 2.25),
      verticalCenter: _clamp01(sc.dy * 0.55 + hc.dy * 0.45),
      tilt: tilt * 0.6,
    );
  }

  // Bottoms: waist → ankles (or knees).
  if (has(const [
    'pant', 'trouser', 'jean', 'short', 'skirt', 'legging', 'bottom',
    'chino', 'capri',
  ])) {
    final lower = ac ?? kc;
    if (hc == null || lower == null) return null;
    final span = hs ?? ss ?? 0.3;
    return AnchoredPlacement(
      widthFactor: _clampW(span * 1.9),
      verticalCenter: _clamp01((hc.dy + lower.dy) / 2),
      tilt: tilt * 0.35,
    );
  }

  // Shoes: at the ankles.
  if (has(const ['shoe', 'sneaker', 'boot', 'heel', 'sandal', 'loafer', 'trainer'])) {
    if (ac == null) return null;
    final span = hs ?? ss ?? 0.3;
    return AnchoredPlacement(
      widthFactor: _clampW(span * 1.1),
      verticalCenter: _clamp01(ac.dy),
      tilt: 0,
    );
  }

  // Tops + any remaining torso garment: shoulders → upper waist.
  if (sc == null || hc == null || ss == null) return null;
  return AnchoredPlacement(
    widthFactor: _clampW(ss * 2.05),
    verticalCenter: _clamp01(sc.dy * 0.6 + hc.dy * 0.4),
    tilt: tilt * 0.6,
  );
}

/// The rect a `BoxFit.contain` image occupies inside [canvas], given the image's
/// aspect ratio (w/h). Used to map image-space landmarks to canvas coordinates.
Rect containImageRect(Size canvas, double imageAspect) {
  if (imageAspect <= 0 || canvas.width <= 0 || canvas.height <= 0) {
    return Offset.zero & canvas;
  }
  final canvasAspect = canvas.width / canvas.height;
  double w;
  double h;
  if (imageAspect > canvasAspect) {
    w = canvas.width;
    h = w / imageAspect;
  } else {
    h = canvas.height;
    w = h * imageAspect;
  }
  return Rect.fromLTWH((canvas.width - w) / 2, (canvas.height - h) / 2, w, h);
}

/// Converts an image-space [AnchoredPlacement] to the editor's CANVAS-fraction
/// model (width as a fraction of canvas width; vertical centre as a fraction of
/// canvas height), accounting for the contained image's letterboxing.
({double widthFactor, double verticalCenter, double tilt}) toCanvasPlacement(
  AnchoredPlacement ap,
  Size canvas,
  double imageAspect,
) {
  final rect = containImageRect(canvas, imageAspect);
  final widthFactor = (ap.widthFactor * rect.width) / canvas.width;
  final centerY = rect.top + ap.verticalCenter * rect.height;
  return (
    widthFactor: widthFactor,
    verticalCenter: centerY / canvas.height,
    tilt: ap.tilt,
  );
}
