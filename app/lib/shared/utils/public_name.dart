/// A name safe to show on a public/community surface (CLAUDE.md §10).
///
/// Returns the first candidate that is non-empty and not an email; `null` when
/// none is safe, so callers fall back to their own neutral label ("Someone")
/// — never to the auth email. The backend already scrubs public names, so this
/// is defense-in-depth for any stale/legacy value that still carries an email.
library;

final RegExp _emailPattern = RegExp(
  r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
);

/// First of [primary], [secondary] that is safe to display publicly.
String? publicName(String? primary, [String? secondary]) {
  for (final candidate in [primary, secondary]) {
    final name = candidate?.trim() ?? '';
    if (name.isEmpty) continue;
    if (_emailPattern.hasMatch(name)) continue;
    return name;
  }
  return null;
}

/// True when [text] contains an email-like token. Used to keep raw emails out of
/// public community captions before they're submitted (CLAUDE.md §10) — the
/// backend rejects them too, this just fails fast with a friendly message.
bool containsEmail(String? text) =>
    text != null && _emailPattern.hasMatch(text);
