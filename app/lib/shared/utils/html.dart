/// Lightweight HTML helpers for RSS-sourced text — no extra dependency.
/// Used to keep raw `<p>`, `<img>`, `src=` and URLs out of the Newsroom (spec).
library;

final _tag = RegExp(r'<[^>]*>');
final _imgSrc = RegExp(r'''<img[^>]*src=["']([^"']+)["']''', caseSensitive: false);
final _numEntity = RegExp(r'&#(\d+);');
final _whitespace = RegExp(r'\s+');

const _entities = <String, String>{
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&apos;': "'",
  '&nbsp;': ' ',
  '&hellip;': '…',
  '&mdash;': '—',
  '&ndash;': '–',
  '&rsquo;': "'",
  '&lsquo;': "'",
  '&ldquo;': '"',
  '&rdquo;': '"',
};

/// Strips tags, decodes common entities, and collapses whitespace into clean,
/// readable prose. Returns an empty string for null/empty input.
String stripHtml(String? input) {
  if (input == null || input.isEmpty) return '';
  var s = input.replaceAll(_tag, ' ');
  _entities.forEach((k, v) => s = s.replaceAll(k, v));
  s = s.replaceAllMapped(_numEntity, (m) {
    final code = int.tryParse(m.group(1)!);
    return code == null ? '' : String.fromCharCode(code);
  });
  return s.replaceAll(_whitespace, ' ').trim();
}

/// First `<img src>` URL embedded in the HTML, if any (absolute http(s) only).
String? extractImageUrl(String? input) {
  if (input == null || input.isEmpty) return null;
  final url = _imgSrc.firstMatch(input)?.group(1)?.trim();
  if (url == null || url.isEmpty || !url.startsWith('http')) return null;
  return url;
}
