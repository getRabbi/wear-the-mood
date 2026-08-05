"""Affiliate destination resolution and validation (DISCOVER spec §18, §38).

This module answers one question — "where may this click go?" — and it is the
only place allowed to answer it. Everything here exists because an outbound
redirect is the classic open-redirect vector: a shopping app that will open
whatever string a row happens to contain is a phishing relay with a fashion
skin on it.

Three rules make that impossible rather than unlikely:

* **The host comes from configuration, never from row data.** A merchant's URL
  template supplies the scheme and host; the product's ``affiliate_ref`` is
  substituted PERCENT-ENCODED into it, so a ref containing ``&``, ``#``, or an
  entire second URL is a literal path segment, not an escape hatch.

* **The final URL is re-parsed and checked against the merchant's own
  allow-list.** Not the template's host — the ALLOW-LIST's. A mistyped or
  tampered template that resolves off-domain is rejected, and a merchant with
  an empty allow-list cannot be redirected to at all.

* **Only ``https``, only the default port, never userinfo.** ``javascript:``,
  ``data:``, custom app schemes, ``https://evil@merchant.test`` and
  ``https://merchant.test:8080`` are all refused by name.

The affiliate tag is a secret (it identifies the account that gets paid), so it
is added at the very end and never appears in an error message, a log line, or
a stored row.
"""

from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import parse_qsl, quote, urlencode, urlsplit, urlunsplit

# A destination longer than this is not a product page, it is an attempt to
# find a buffer somewhere downstream.
MAX_URL_LENGTH = 2048

# ASCII control characters plus space. A URL containing one of these has been
# assembled wrong, and some clients silently strip them — which is exactly how
# a validated string turns into a different destination after validation.
_FORBIDDEN_CHARS = frozenset(chr(c) for c in range(0x21)) | {chr(0x7F)}


class AffiliateError(Exception):
    """A destination could not be produced safely.

    ``reason`` is a short code for logs and metrics. It is deliberately coarse:
    the caller turns every one of these into the same opaque client-facing
    error, because telling a caller *why* a redirect failed validation is a
    free probe of the allow-list.
    """

    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


@dataclass(frozen=True)
class MerchantRedirect:
    """The configuration a merchant's destination is built from."""

    allowed_domains: tuple[str, ...]
    url_template: str | None = None
    affiliate_tag: str | None = None
    tag_param: str = "tag"
    status: str = "ok"


def normalize_domain(value: str) -> str:
    """An allow-list entry reduced to a bare comparable host.

    Tolerates the shapes an operator actually types — ``https://Shop.Example``,
    ``shop.example/``, a leading dot — and rejects a wildcard outright. ``*``
    or ``*.example`` in an allow-list would defeat the point of having one, so
    it is dropped rather than interpreted generously.
    """
    host = value.strip().lower()
    if not host or "*" in host:
        return ""
    if "//" in host:
        host = host.split("//", 1)[1]
    host = host.split("/", 1)[0].split("@")[-1].split(":", 1)[0]
    return host.strip(".")


def host_is_allowed(host: str, allowed_domains: tuple[str, ...] | list[str]) -> bool:
    """Whether ``host`` is an allow-listed domain or a subdomain of one.

    The suffix check is anchored on a dot on purpose: ``example.test`` must not
    match ``notexample.test``, which a bare ``endswith`` would happily accept.
    """
    candidate = (host or "").strip().lower().strip(".")
    if not candidate:
        return False
    for raw in allowed_domains:
        domain = normalize_domain(raw)
        if not domain:
            continue
        if candidate == domain or candidate.endswith("." + domain):
            return True
    return False


def _validated(url: str, allowed_domains: tuple[str, ...] | list[str]) -> str:
    """Every check a finished destination has to pass, in one place."""
    if not url or len(url) > MAX_URL_LENGTH:
        raise AffiliateError("url_length")
    if any(ch in _FORBIDDEN_CHARS for ch in url):
        raise AffiliateError("url_charset")

    try:
        parts = urlsplit(url)
    except ValueError as exc:  # malformed IPv6 literal, bad port, …
        raise AffiliateError("url_malformed") from exc

    # `https` only. This is what refuses `javascript:`, `data:`, `file:`, plain
    # `http:` and any custom app scheme that would leave the browser sandbox.
    if parts.scheme.lower() != "https":
        raise AffiliateError("scheme")
    # Credentials in a URL are a phishing display trick before they are
    # anything else: `https://merchant.test@evil.test` renders as the merchant.
    if "@" in parts.netloc:
        raise AffiliateError("userinfo")
    try:
        port = parts.port
    except ValueError as exc:
        raise AffiliateError("port") from exc
    if port not in (None, 443):
        raise AffiliateError("port")
    if not parts.hostname:
        raise AffiliateError("host_missing")
    if not host_is_allowed(parts.hostname, allowed_domains):
        raise AffiliateError("host_not_allowed")
    return url


def _with_tag(url: str, tag: str | None, tag_param: str) -> str:
    """Appends the affiliate tag, replacing any existing value of that key.

    Done after validation and by rebuilding the query properly, so the tag
    cannot be smuggled into the host and a ref that already carried the
    parameter cannot end up with two conflicting values.
    """
    if not tag:
        return url
    parts = urlsplit(url)
    query = [(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True) if k != tag_param]
    query.append((tag_param, tag))
    return urlunsplit(
        (parts.scheme, parts.netloc, parts.path, urlencode(query, doseq=True), parts.fragment)
    )


def resolve_destination(affiliate_ref: str | None, config: MerchantRedirect) -> tuple[str, str]:
    """The safe destination for one product, as ``(url, host)``.

    ``affiliate_ref`` is either a merchant-side product id to substitute into
    the template, or an absolute https URL the merchant's feed supplied
    directly. Both paths end at the same allow-list check — an absolute ref is
    not trusted more than a templated one just because it arrived complete.

    Raises [AffiliateError] rather than returning a partial result: there is no
    safe fallback destination, and "somewhere roughly right" is precisely the
    failure mode this function exists to prevent.
    """
    ref = (affiliate_ref or "").strip()
    if not ref:
        raise AffiliateError("ref_missing")
    if config.status != "ok":
        # A paused or revoked agreement stops earning clicks rather than
        # sending users out under a tag nobody is honouring any more.
        raise AffiliateError("merchant_status")
    if not any(normalize_domain(d) for d in config.allowed_domains):
        # No allow-list means no redirect. Defaulting to "allow" here would
        # make every un-configured merchant an open redirect.
        raise AffiliateError("no_allowed_domains")

    if "://" in ref:
        # An absolute destination from the feed. Validated exactly like a
        # templated one; the allow-list is what decides, not the fact that the
        # merchant sent a whole URL.
        url = _validated(ref, config.allowed_domains)
        tag_already_placed = False
    else:
        template = (config.url_template or "").strip()
        if not template or "{ref}" not in template:
            raise AffiliateError("template_missing")
        # Percent-encode with an empty safe set so `/`, `?`, `#`, `&` and `:`
        # are all escaped. This is the substitution that makes a hostile ref
        # inert: it can only ever widen the path, never change the host.
        tag_already_placed = "{tag}" in template
        url = template.replace("{ref}", quote(ref, safe="")).replace(
            "{tag}", quote(config.affiliate_tag or "", safe="")
        )
        url = _validated(url, config.allowed_domains)

    # The tag goes on last — unless the template already positioned it, in
    # which case appending would send two conflicting values and some networks
    # resolve that by paying neither. The result is validated once more:
    # appending a parameter must not be able to change the host, and proving
    # that costs one more parse.
    if not tag_already_placed:
        url = _with_tag(url, config.affiliate_tag, config.tag_param)
    final = _validated(url, config.allowed_domains)
    host = (urlsplit(final).hostname or "").lower()
    return final, host
