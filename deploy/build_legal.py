"""Render the legal/*.md sources into styled static HTML for hosting.

`legal/*.md` is the single source of truth for the public policies. This script
strips the internal "> ..." notes (never published) and writes self-contained
HTML to deploy/site/legal/, served at
wearthemood.com/legal/{privacy,terms,acceptable-use}. Re-run after editing the
markdown:  python deploy/build_legal.py

Maintenance notes:
  * The **publication date is pinned PER PAGE** (PAGE_DATES) and must match that
    file's own "Last updated:" line. Bump a page's date only when THAT page's
    text changes — a legal page whose date moves because a different document was
    edited is worse than useless, and a shared date forced exactly that.
  * The **service-provider list in privacy.md must stay accurate**. The
    DigitalOcean droplet was decommissioned after the 2026-07-20 migration;
    naming a provider that no longer processes user data (or omitting one that
    does) makes the disclosure false and can get the app removed.
  * Values are written literally in the markdown — there are no {{PLACEHOLDER}}
    substitutions any more. `fill()` still hard-fails on a stray {{...}} so a
    template fragment can never reach production.
"""

from __future__ import annotations

import re
from datetime import date
from pathlib import Path

import markdown  # pip install markdown (MIT)

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "legal"
OUT = ROOT / "deploy" / "site" / "legal"

# Pinned publication date — keep in sync with the "Last updated:" line in each
# legal/*.md. Deliberately NOT date.today(): a published date must change only
# when that document's own text does.
PAGE_DATES = {
    # Rewritten for the AI-processing / face-data disclosure (Apple 5.1.1(i)).
    "privacy.md": date(2026, 8, 12),
    "terms.md": date(2026, 8, 2),
    "acceptable-use.md": date(2026, 8, 2),
}

#: Newest publication date across all pages — the footer's copyright year.
LAST_UPDATED = max(PAGE_DATES.values())

PAGES = {
    "privacy.md": ("privacy.html", "Privacy Policy"),
    "terms.md": ("terms.html", "Terms of Service"),
    "acceptable-use.md": ("acceptable-use.html", "Acceptable Use Policy"),
}

SUPPORT_EMAIL = "uprightseo24@gmail.com"

SHELL = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} — Wear The Mood</title>
<style>
  :root {{ --ink:#1a1a1a; --graphite:#6b6b6b; --mist:#e7e4df; --paper:#faf8f5; --accent:#b44c2e; }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--paper); color:var(--ink);
    font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif; }}
  .wrap {{ max-width:760px; margin:0 auto; padding:48px 22px 96px; }}
  .brand {{ font-weight:700; letter-spacing:.3px; color:var(--accent); text-decoration:none; font-size:15px; }}
  h1 {{ font-size:32px; line-height:1.15; margin:18px 0 6px; }}
  h2 {{ font-size:21px; margin:38px 0 10px; }}
  h3 {{ font-size:17px; margin:26px 0 8px; }}
  p, li {{ color:#252525; }}
  a {{ color:var(--accent); }}
  hr {{ border:0; border-top:1px solid var(--mist); margin:28px 0; }}
  table {{ border-collapse:collapse; width:100%; margin:14px 0; font-size:14.5px; }}
  th, td {{ border:1px solid var(--mist); padding:9px 11px; text-align:left; vertical-align:top; }}
  th {{ background:#f1ede7; }}
  code {{ background:#f1ede7; padding:1px 5px; border-radius:5px; }}
  .meta {{ color:var(--graphite); font-size:14px; }}
  footer {{ margin-top:56px; padding-top:18px; border-top:1px solid var(--mist); color:var(--graphite); font-size:13.5px; }}
  footer a {{ margin-right:14px; }}
</style>
</head>
<body>
  <div class="wrap">
    <a class="brand" href="/">WEAR THE MOOD</a>
    {body}
    <footer>
      <a href="/legal/privacy">Privacy</a>
      <a href="/legal/terms">Terms</a>
      <a href="/legal/acceptable-use">Acceptable Use</a>
      <a href="/delete-account">Delete account</a>
      <div style="margin-top:8px">© {year} Wear The Mood · {email}</div>
    </footer>
  </div>
</body>
</html>
"""

# NOTE: the public landing page (deploy/site/index.html) is a hand-maintained
# static site (deploy/site/index.html + assets/). This script must NOT generate or
# overwrite it — it only renders the legal pages from legal/*.md. (It used to write
# a tiny placeholder index.html here; that was removed so legal rebuilds never
# clobber the real landing page.)


def fill(text: str) -> str:
    # Strip the internal note blockquote(s) — not for public eyes.
    text = "\n".join(ln for ln in text.splitlines() if not ln.lstrip().startswith(">"))
    # Catch any leftover placeholder so we never publish a raw {{...}}.
    leftover = re.findall(r"\{\{[^}]+\}\}", text)
    if leftover:
        raise SystemExit(f"Unfilled placeholders: {sorted(set(leftover))}")
    return text


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    md = markdown.Markdown(extensions=["tables", "sane_lists", "attr_list"])
    for src, (out_name, title) in PAGES.items():
        published = PAGE_DATES[src]
        stamp = f"{published:%B} {published.day}, {published.year}"
        raw = (SRC / src).read_text(encoding="utf-8")
        if f"**Last updated:** {stamp}" not in raw:
            raise SystemExit(
                f"{src}: 'Last updated:' does not match PAGE_DATES[{src!r}] "
                f"({stamp}). Bump both together."
            )
        body = md.reset().convert(fill(raw))
        html = SHELL.format(
            title=title, body=body, year=LAST_UPDATED.year, email=SUPPORT_EMAIL
        )
        (OUT / out_name).write_text(html, encoding="utf-8")
        print(f"wrote {out_name} ({len(html)} bytes)")
    # NB: index.html (the landing page) is intentionally NOT written here — it is a
    # hand-maintained static site under deploy/site/.


if __name__ == "__main__":
    main()
