/// Asking a publisher's own image CDN for the size we are actually going to
/// draw.
///
/// FIRST-PARTY media (closet cutouts, giveaway covers, post images) already
/// arrives correctly sized: the backend writes a 512px WebP thumbnail alongside
/// every object and the API hands the thumbnail to list surfaces. THIRD-PARTY
/// editorial media does not — a news item carries whatever URL its RSS feed
/// published, and for the feeds this app ingests that URL is the uncropped
/// master.
///
/// Measured against production content (2026-08-14, 1 503 articles with images,
/// 1 283 of them from `assets.vogue.com`):
///
/// ```text
/// master/pass  3000×4500   717 KB   → w_320  320×480    27 KB   (26× smaller)
/// master/pass  3024×4032  1.72 MB   → w_320  320×427    35 KB   (50× smaller)
/// master/pass  3586×4482  7.94 MB   → w_320  320×400    64 KB  (123× smaller)
/// ```
///
/// The 7.94 MB one was being downloaded to fill a 96×112 dp list thumbnail.
/// `memCacheWidth` never helped: it caps the DECODE, so the whole master still
/// crosses the network and is still parsed in full. That is the Newsroom delay,
/// and the same URLs feed the Discover story rail and the editorial card, which
/// is why those felt slow too.
///
/// The rewrite is deliberately narrow. It is an allow-list of hosts whose
/// transform grammar is part of their public URL, applied only to the
/// untransformed form, and everything else — including a host that publishes a
/// derivative we did not ask for — passes through byte-for-byte. Fashionista is
/// the case that proves the caution is needed: its feed URLs already carry
/// `?profile=rss`, which IS the small rendition, and adding a `width=` to them
/// returns an image nearly 3× LARGER.
library;

/// Widths we are willing to ask for.
///
/// A ladder rather than the exact pixel width, so two cards a few pixels apart
/// share one cached object instead of each minting their own. Requests round UP
/// to the next rung — never down, which would put a soft image on screen.
const _ladder = <int>[320, 480, 640, 960, 1280];

/// Condé Nast's asset hosts, whose photo URLs are
/// `…/photos/<id>/<derivative>/<transform>/<file>`.
///
/// Named explicitly rather than matched by shape: the news sources are a
/// curated list, and a URL that merely LOOKS like this grammar on some other
/// host is a rewrite we have not verified.
const _condeNastHosts = <String>{
  'assets.vogue.com',
  'assets.vanityfair.com',
  'assets.gq.com',
  'media.gq.com',
  'assets.wmagazine.com',
  'assets.teenvogue.com',
};

/// `pass` is Condé Nast's "no transform — serve the master" token. It is the
/// only transform we replace; a publisher-chosen crop is left alone.
const _condeNastMasterToken = 'pass';

/// The URL to request for drawing [url] at [width] device pixels.
///
/// Returns [url] unchanged whenever there is nothing verified to do — an empty
/// or relative URL, an unknown host, an already-transformed asset. Callers can
/// therefore use this unconditionally; it is never a decision they have to make
/// per surface.
String imageRenditionUrl(String url, {required int width}) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return url;

  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return url;
  if (uri.scheme != 'https' && uri.scheme != 'http') return url;

  if (_condeNastHosts.contains(uri.host.toLowerCase())) {
    return _condeNast(uri, renditionWidth(width)) ?? url;
  }
  return url;
}

/// The ladder rung [width] rounds up to. Exposed so a test can state the rule
/// once instead of restating the ladder.
int renditionWidth(int width) {
  for (final rung in _ladder) {
    if (width <= rung) return rung;
  }
  return _ladder.last;
}

/// `…/photos/<id>/<derivative>/pass/<file>` → `…/<derivative>/w_<W>,c_limit/<file>`.
///
/// `c_limit` scales DOWN only, so an asset already narrower than the request
/// comes back untouched rather than upscaled into a soft one.
///
/// Returns null when the path is not the shape we know, which the caller reads
/// as "leave it alone".
String? _condeNast(Uri uri, int width) {
  final segments = uri.pathSegments;
  // photos / <id> / <derivative> / <transform> / <file…>
  if (segments.length < 5) return null;
  if (segments[0] != 'photos') return null;
  if (segments[3] != _condeNastMasterToken) return null;

  final rewritten = [...segments]..[3] = 'w_$width,c_limit';
  return uri.replace(pathSegments: rewritten).toString();
}
