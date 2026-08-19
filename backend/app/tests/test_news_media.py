"""News hero-image resolution, validation, precedence and lifecycle (Issue 3).

The production symptom: Vogue cards carried a photograph and Hypebeast /
Highsnobiety cards carried the gradient placeholder, on the same screen, from
the same ingest. These tests pin each half of why.

Every publisher request is served by a transport stub — the suite must never
reach out to a real newsroom.
"""

from __future__ import annotations

import asyncio
import io

import httpx
import pytest

from app.services.news.media import (
    MIN_HERO_EDGE,
    SOURCE_FEED_HTML,
    SOURCE_OG_IMAGE,
    SOURCE_RSS_ENCLOSURE,
    SOURCE_RSS_MEDIA,
    SOURCE_TWITTER_IMAGE,
    STATUS_FORBIDDEN,
    STATUS_MISSING,
    STATUS_NOT_IMAGE,
    STATUS_OK,
    STATUS_TOO_SMALL,
    STATUS_UNREACHABLE,
    USER_AGENT,
    MediaCandidate,
    ResolvedMedia,
    feed_candidates,
    page_candidates,
    resolve_article_media,
    validate_candidate,
)


def _png(width: int, height: int) -> bytes:
    from PIL import Image

    buf = io.BytesIO()
    Image.new("RGB", (width, height), (120, 40, 60)).save(buf, format="PNG")
    return buf.getvalue()


HERO = _png(1200, 800)
PIXEL = _png(1, 1)
LOGO = _png(64, 64)


def _client(handler) -> httpx.AsyncClient:
    return httpx.AsyncClient(
        transport=httpx.MockTransport(handler),
        follow_redirects=True,
        headers={"User-Agent": USER_AGENT},
    )


def _serve(routes: dict[str, httpx.Response]):
    def handler(request: httpx.Request) -> httpx.Response:
        return routes.get(str(request.url), httpx.Response(404, text="not found"))

    return handler


def _image_response(data: bytes = HERO) -> httpx.Response:
    return httpx.Response(200, content=data, headers={"content-type": "image/png"})


# ── candidate collection: every convention a publisher might use ─────────────


def test_vogue_shaped_feed_declares_its_image() -> None:
    entry = {"media_content": [{"url": "https://assets.vogue.com/a.jpg"}]}
    found = feed_candidates(entry, "")
    assert found[0] == MediaCandidate("https://assets.vogue.com/a.jpg", SOURCE_RSS_MEDIA)


def test_an_enclosure_is_a_declaration_too() -> None:
    entry = {"links": [{"type": "image/jpeg", "href": "https://cdn/enc.jpg"}]}
    assert feed_candidates(entry, "")[0].provenance == SOURCE_RSS_ENCLOSURE


def test_hypebeast_shaped_feed_hides_its_image_in_the_description() -> None:
    # No media:*, no enclosure — the picture is an <img> inside the summary HTML.
    # This is the case that produced a blank card next to a working Vogue one.
    body = '<p>Story</p><img src="https://hypebeast.com/img/hero.jpg" />'
    found = feed_candidates({}, body)
    assert found == [MediaCandidate("https://hypebeast.com/img/hero.jpg", SOURCE_FEED_HTML)]


def test_declarations_are_tried_before_inferences() -> None:
    entry = {"media_thumbnail": [{"url": "https://cdn/declared.jpg"}]}
    body = '<img src="https://cdn/inferred.jpg" />'
    assert [c.provenance for c in feed_candidates(entry, body)] == [
        SOURCE_RSS_MEDIA,
        SOURCE_FEED_HTML,
    ]


def test_a_data_uri_is_never_a_candidate() -> None:
    body = '<img src="data:image/gif;base64,R0lGOD" />'
    assert feed_candidates({}, body) == []


def test_highsnobiety_shaped_feed_offers_nothing_at_all() -> None:
    assert feed_candidates({}, "<p>Just words.</p>") == []


def test_og_image_is_read_from_the_article_page() -> None:
    # The step ingestion previously declined to take, and the ONLY thing that
    # gives a Highsnobiety-shaped source a picture.
    html = '<meta property="og:image" content="https://cdn/og.jpg">'
    found = page_candidates(html, base_url="https://highsnobiety.com/p/story")
    assert found == [MediaCandidate("https://cdn/og.jpg", SOURCE_OG_IMAGE)]


def test_og_beats_twitter_when_both_exist() -> None:
    html = (
        '<meta name="twitter:image" content="https://cdn/tw.jpg">'
        '<meta property="og:image" content="https://cdn/og.jpg">'
    )
    found = page_candidates(html, base_url="https://x.com/a")
    assert [c.provenance for c in found] == [SOURCE_OG_IMAGE, SOURCE_TWITTER_IMAGE]


def test_a_relative_og_image_is_resolved_against_the_article() -> None:
    html = '<meta property="og:image" content="/media/hero.jpg">'
    found = page_candidates(html, base_url="https://pub.example/news/story")
    assert found[0].url == "https://pub.example/media/hero.jpg"


# ── validation: a URL is not an image until it proves it ─────────────────────


def test_a_real_image_validates_and_reports_its_geometry() -> None:
    url = "https://cdn/hero.png"
    client = _client(_serve({url: _image_response()}))
    result = asyncio.run(validate_candidate(client, MediaCandidate(url, SOURCE_RSS_MEDIA)))
    assert result.status == STATUS_OK
    assert (result.width, result.height) == (1200, 800)
    assert result.aspect_ratio == 1.5
    assert result.provenance == SOURCE_RSS_MEDIA


def test_a_dead_link_is_unreachable_not_ok() -> None:
    client = _client(_serve({}))
    result = asyncio.run(
        validate_candidate(client, MediaCandidate("https://cdn/gone.jpg", SOURCE_RSS_MEDIA))
    )
    assert result.status == STATUS_UNREACHABLE


def test_an_html_error_page_is_not_an_image() -> None:
    url = "https://cdn/oops"
    client = _client(
        _serve({url: httpx.Response(200, text="<html>", headers={"content-type": "text/html"})})
    )
    result = asyncio.run(validate_candidate(client, MediaCandidate(url, SOURCE_FEED_HTML)))
    assert result.status == STATUS_NOT_IMAGE


@pytest.mark.parametrize("data", [PIXEL, LOGO])
def test_tracking_pixels_and_logos_are_refused(data: bytes) -> None:
    url = "https://cdn/tiny.png"
    client = _client(_serve({url: _image_response(data)}))
    result = asyncio.run(validate_candidate(client, MediaCandidate(url, SOURCE_FEED_HTML)))
    assert result.status == STATUS_TOO_SMALL
    assert min(result.width or 0, result.height or 0) < MIN_HERO_EDGE


@pytest.mark.parametrize("code", [401, 403, 451])
def test_a_publisher_refusal_is_recorded_and_respected(code: int) -> None:
    """We do not forge a Referer, pretend to be a browser, or retry by other
    means. A publisher that blocks hotlinking has answered."""
    url = "https://cdn/blocked.jpg"
    client = _client(_serve({url: httpx.Response(code)}))
    result = asyncio.run(validate_candidate(client, MediaCandidate(url, SOURCE_RSS_MEDIA)))
    assert result.status == STATUS_FORBIDDEN


def test_we_identify_ourselves_honestly() -> None:
    assert "WearTheMoodBot" in USER_AGENT
    assert "Mozilla" not in USER_AGENT, "a browser string would be evasion"


def test_a_redirect_stores_where_it_landed() -> None:
    start, final = "https://cdn/redir.png", "https://cdn2/real.png"
    routes = {
        start: httpx.Response(301, headers={"location": final}),
        final: _image_response(),
    }
    client = _client(_serve(routes))
    result = asyncio.run(validate_candidate(client, MediaCandidate(start, SOURCE_RSS_MEDIA)))
    assert result.status == STATUS_OK
    assert result.url == final, "the client should not repeat the hop"


def test_a_malformed_url_is_rejected_without_a_request() -> None:
    client = _client(_serve({}))
    result = asyncio.run(validate_candidate(client, MediaCandidate("notaurl", SOURCE_FEED_HTML)))
    assert result.status == "invalid_url"


# ── the resolver end to end, per publisher shape ─────────────────────────────


def _resolve(entry, body, article_url, routes):
    client = _client(_serve(routes))
    return asyncio.run(
        resolve_article_media(entry=entry, body=body, article_url=article_url, client=client)
    )


def test_vogue_resolves_from_the_feed_without_touching_the_page() -> None:
    url = "https://assets.vogue.com/hero.png"
    result = _resolve(
        {"media_content": [{"url": url}]}, "", "https://vogue.com/a", {url: _image_response()}
    )
    assert result.ok
    assert result.provenance == SOURCE_RSS_MEDIA


def test_hypebeast_resolves_from_the_description_html() -> None:
    url = "https://hypebeast.com/hero.png"
    result = _resolve({}, f'<img src="{url}">', "https://hypebeast.com/a", {url: _image_response()})
    assert result.ok
    assert result.provenance == SOURCE_FEED_HTML


def test_highsnobiety_resolves_only_via_the_article_page() -> None:
    article = "https://highsnobiety.com/p/story"
    image = "https://cdn.highsnobiety.com/hero.png"
    routes = {
        article: httpx.Response(
            200,
            text=f'<meta property="og:image" content="{image}">',
            headers={"content-type": "text/html"},
        ),
        image: _image_response(),
    }
    result = _resolve({}, "<p>words</p>", article, routes)
    assert result.ok
    assert result.provenance == SOURCE_OG_IMAGE
    assert result.url == image


def test_a_broken_feed_image_falls_through_to_the_page() -> None:
    # The feed declares an image that 404s; the page has a good one. The article
    # keeps its picture instead of losing it to a stale CDN link.
    article = "https://pub.example/a"
    good = "https://cdn/good.png"
    routes = {
        article: httpx.Response(
            200,
            text=f'<meta property="og:image" content="{good}">',
            headers={"content-type": "text/html"},
        ),
        good: _image_response(),
    }
    result = _resolve({"media_content": [{"url": "https://cdn/dead.jpg"}]}, "", article, routes)
    assert result.ok
    assert result.provenance == SOURCE_OG_IMAGE


def test_an_article_with_no_image_anywhere_says_so_precisely() -> None:
    article = "https://pub.example/textonly"
    routes = {
        article: httpx.Response(200, text="<html></html>", headers={"content-type": "text/html"})
    }
    result = _resolve({}, "<p>words</p>", article, routes)
    assert not result.ok
    assert result.status == STATUS_MISSING
    assert result.url is None, "never invent an image for a story that has none"


def test_the_page_is_not_fetched_when_the_feed_already_worked() -> None:
    seen: list[str] = []
    url = "https://cdn/hero.png"

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(str(request.url))
        return _image_response()

    client = _client(handler)
    result = asyncio.run(
        resolve_article_media(
            entry={"media_content": [{"url": url}]},
            body="",
            article_url="https://pub.example/a",
            client=client,
        )
    )
    assert result.ok
    assert seen == [url], "a well-behaved publisher should cost one request"


# ── the upsert must not undo a good resolution ───────────────────────────────


def test_reingest_cannot_null_out_a_validated_image() -> None:
    """The defect that would have made any repair pointless.

    `image_url = excluded.image_url` meant the next cron tick overwrote a
    working hero image with whatever the feed said this time — including
    nothing. Asserted against the SQL, the way this suite asserts every other
    hard rule it cannot reach a database for.
    """
    from app.services.news.pipeline import _UPSERT

    assert "image_url = excluded.image_url" not in _UPSERT
    # A validated resolution wins; an unvalidated one may not clobber a good one.
    assert "when excluded.image_status = 'ok' then excluded.image_url" in _UPSERT
    assert "when news_items.image_status = 'ok' then news_items.image_url" in _UPSERT


def test_reingest_still_replaces_a_stale_image_when_proven_better() -> None:
    from app.services.news.pipeline import _UPSERT

    # Precedence, not "first write wins": a fresh OK always overwrites.
    ok_branch = _UPSERT.index("when excluded.image_status = 'ok'")
    keep_branch = _UPSERT.index("when news_items.image_status = 'ok'")
    assert ok_branch < keep_branch, "a newly validated image must take priority"


def _assigned_columns(sql: str) -> set[str]:
    """The columns an UPDATE actually writes — parsed, not grepped.

    Substring matching is useless here: `image_url = ...` contains `url =`, so a
    naive check reports the repair rewriting the article link when it is doing
    nothing of the sort.
    """
    body = sql.split(" set ", 1)[1].split(" where ", 1)[0]
    depth = 0
    current = ""
    parts: list[str] = []
    for char in body:
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        if char == "," and depth == 0:
            parts.append(current)
            current = ""
            continue
        current += char
    parts.append(current)
    return {p.strip().split("=", 1)[0].strip() for p in parts if "=" in p}


def test_the_repair_writes_image_columns_and_nothing_else() -> None:
    from app.scripts.repair_news_media import _UPDATE

    written = _assigned_columns(_UPDATE)
    assert written, "the update must actually write something"
    assert all(c.startswith("image_") for c in written), (
        f"a repair that edits editorial copy is not a repair: {sorted(written)}"
    )
    assert "image_status" in written


def test_the_repair_is_read_only_until_asked() -> None:
    import ast
    import inspect

    from app.scripts import repair_news_media

    source = inspect.getsource(repair_news_media.repair)
    assert "if apply:" in source, "writes must be behind the --apply flag"

    # No upload path AT ALL — no publisher image can reach Wear The Mood
    # storage, whatever a source's cache policy says. Checked against parsed
    # CODE rather than the file text, so the prose above (which says the words
    # out loud) cannot satisfy or break the assertion.
    tree = ast.parse(inspect.getsource(repair_news_media))
    names: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Name):
            names.add(node.id.lower())
        elif isinstance(node, ast.Attribute):
            names.add(node.attr.lower())
        elif isinstance(node, ast.alias):
            names.add(node.name.lower().rsplit(".", 1)[-1])
    for forbidden in ("upload", "put_object", "insert_asset", "get_storage_provider"):
        assert forbidden not in names, f"the repair must not be able to {forbidden}"


# ── lifecycle: unreviewed and archived stories are not editorial ─────────────


def test_only_published_stories_are_served() -> None:
    from app.routers.v1.news import _IMAGE_OK, _PUBLIC

    assert _PUBLIC == "status = 'published'"
    assert "image_status = 'ok'" in _IMAGE_OK
    assert "image_url is not null" in _IMAGE_OK


# ── the repair tool: dry-run, idempotent, resumable ──────────────────────────


class _FakeConn:
    """Just enough asyncpg for the repair: a worklist and a write log."""

    def __init__(self, rows: list[dict]) -> None:
        self._rows = rows
        self.writes: list[tuple] = []

    async def fetch(self, sql: str, *args):
        # The repair asks for rows whose media was never resolved (or failed).
        assert "image_status is null" in sql
        limit = args[0]
        return self._rows[:limit]

    async def execute(self, sql: str, *args) -> None:
        self.writes.append(args)


def _row(row_id: str, source: str, url: str, image: str | None = None) -> dict:
    return {
        "id": row_id,
        "url": url,
        "canonical_url": url,
        "image_url": image,
        "image_status": None,
        "source_name": source,
    }


def _fake_resolver(answers: dict[str, ResolvedMedia]):
    async def resolve(*, entry, body, article_url, client=None):
        return answers.get(article_url, ResolvedMedia(STATUS_MISSING))

    return resolve


def _repair(rows, answers, *, apply: bool):
    from app.scripts.repair_news_media import repair

    conn = _FakeConn(rows)
    result = asyncio.run(
        repair(
            conn,
            apply=apply,
            limit=100,
            batch=10,
            recheck=False,
            resolver=_fake_resolver(answers),
        )
    )
    return conn, result


_FIXTURE_ROWS = [
    _row("1", "Vogue", "https://vogue.com/a", image="https://cdn/v.jpg"),
    _row("2", "Hypebeast", "https://hypebeast.com/a"),
    _row("3", "Highsnobiety", "https://highsnobiety.com/a"),
    _row("4", "Highsnobiety", "https://highsnobiety.com/b"),
]

_FIXTURE_ANSWERS = {
    "https://vogue.com/a": ResolvedMedia(
        STATUS_OK, url="https://cdn/v.jpg", provenance=SOURCE_RSS_MEDIA, width=1200, height=800
    ),
    "https://hypebeast.com/a": ResolvedMedia(
        STATUS_OK, url="https://cdn/h.jpg", provenance=SOURCE_FEED_HTML, width=1000, height=600
    ),
    "https://highsnobiety.com/a": ResolvedMedia(
        STATUS_OK, url="https://cdn/hs.jpg", provenance=SOURCE_OG_IMAGE, width=1600, height=900
    ),
    "https://highsnobiety.com/b": ResolvedMedia(STATUS_MISSING),
}


def test_a_dry_run_writes_nothing() -> None:
    conn, result = _repair(_FIXTURE_ROWS, _FIXTURE_ANSWERS, apply=False)
    assert conn.writes == [], "a dry run must not touch a single row"
    assert result["examined"] == 4
    assert result["applied"] is False


def test_a_dry_run_reports_what_it_would_recover_per_source() -> None:
    _, result = _repair(_FIXTURE_ROWS, _FIXTURE_ANSWERS, apply=False)
    per_source = result["per_source"]
    # Vogue already worked; Hypebeast and one Highsnobiety row gain a picture
    # they never had; the other Highsnobiety row genuinely has none.
    # Absent means zero: the counter is only written when something recovers.
    assert per_source["Vogue"].get("recovered", 0) == 0
    assert per_source["Hypebeast"]["recovered"] == 1
    assert per_source["Highsnobiety"]["recovered"] == 1
    assert per_source["Highsnobiety"][STATUS_MISSING] == 1
    assert result["totals"]["recovered"] == 2


def test_apply_writes_exactly_one_row_each() -> None:
    conn, result = _repair(_FIXTURE_ROWS, _FIXTURE_ANSWERS, apply=True)
    assert len(conn.writes) == 4
    assert result["totals"]["written"] == 4
    # Every write carries the row id and the status it proved.
    assert {w[0] for w in conn.writes} == {"1", "2", "3", "4"}
    assert [w[1] for w in conn.writes] == [STATUS_OK, STATUS_OK, STATUS_OK, STATUS_MISSING]


def test_re_running_is_idempotent() -> None:
    first, r1 = _repair(_FIXTURE_ROWS, _FIXTURE_ANSWERS, apply=True)
    second, r2 = _repair(_FIXTURE_ROWS, _FIXTURE_ANSWERS, apply=True)
    assert first.writes == second.writes
    assert r1["totals"] == r2["totals"]


def test_the_report_renders_the_per_source_table() -> None:
    from app.scripts.repair_news_media import format_report

    _, result = _repair(_FIXTURE_ROWS, _FIXTURE_ANSWERS, apply=False)
    table = format_report(result)
    assert "Source" in table and "Image OK" in table and "Recovered" in table
    for source in ("Vogue", "Hypebeast", "Highsnobiety"):
        assert source in table
    assert "examined=4" in table
