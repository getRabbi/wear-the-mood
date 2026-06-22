import 'dart:typed_data';

/// Sniffs an image's content type from its magic bytes, so an upload declares the
/// correct type to storage no matter which encoder produced it (§8). Keeps the
/// multi-caller upload paths correct (a compressed WebP, a 2D-composite PNG, a
/// JPEG selfie all flow through the same upload()).
String imageContentType(Uint8List bytes) {
  // WebP: "RIFF"???? "WEBP"
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  // PNG: 89 50 4E 47
  if (bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  return 'image/jpeg';
}

/// A stable cache key for `cached_network_image` that survives signed-URL
/// refreshes (INFRA_UPGRADE 1D, point 4). A private R2/Supabase URL changes only
/// in its query (the expiring signature/token) while its path — which contains
/// the stable object key — stays fixed; keying on the path lets a refreshed URL
/// reuse the cached bytes instead of re-downloading. Public/immutable URLs have
/// no query and key on the whole URL.
String stableImageCacheKey(String url) {
  final q = url.indexOf('?');
  return q == -1 ? url : url.substring(0, q);
}

/// File extension (with dot) for an image content type — used for legacy storage
/// keys so the object name matches its bytes.
String extForImageContentType(String contentType) {
  switch (contentType) {
    case 'image/webp':
      return '.webp';
    case 'image/png':
      return '.png';
    default:
      return '.jpg';
  }
}
