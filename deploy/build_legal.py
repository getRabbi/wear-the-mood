"""Render the legal/*.md drafts into styled static HTML for hosting.

Fills the {{PLACEHOLDERS}}, strips the internal "template — not legal advice"
banners, and writes self-contained HTML to deploy/site/legal/ (served by Caddy
at wearthemood.com/legal/{privacy,terms,acceptable-use}). Re-run after editing
the markdown:  python deploy/build_legal.py
"""

from __future__ import annotations

import re
from datetime import date
from pathlib import Path

import markdown  # pip install markdown (MIT)

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "legal"
OUT = ROOT / "deploy" / "site" / "legal"

# Placeholder values (confirmed with founder; the rest are sensible defaults).
VALUES = {
    "DATE": f"{date.today():%B} {date.today().day}, {date.today().year}",
    "LEGAL_ENTITY_NAME": "Fashion OS",
    "ADDRESS": "Bangladesh",
    "PRIVACY_EMAIL": "support@wearthemood.com",
    "SUPPORT_EMAIL": "support@wearthemood.com",
    "ABUSE_EMAIL": "support@wearthemood.com",
    "HOSTING_REGION/PROVIDER": "DigitalOcean (cloud hosting)",
    "DELETION_WINDOW, e.g. 30 days": "30 days",
    "JURISDICTION": "Bangladesh",
    "CAP_AMOUNT": "USD 100",
}

PAGES = {
    "privacy.md": ("privacy.html", "Privacy Policy"),
    "terms.md": ("terms.html", "Terms of Service"),
    "acceptable-use.md": ("acceptable-use.html", "Acceptable Use Policy"),
}

SHELL = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} — Fashion OS</title>
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
    <a class="brand" href="/">FASHION OS</a>
    {body}
    <footer>
      <a href="/legal/privacy">Privacy</a>
      <a href="/legal/terms">Terms</a>
      <a href="/legal/acceptable-use">Acceptable Use</a>
      <div style="margin-top:8px">© {year} Fashion OS · support@wearthemood.com</div>
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
    # Strip the internal template-warning blockquote(s) — not for public eyes.
    text = "\n".join(ln for ln in text.splitlines() if not ln.lstrip().startswith(">"))
    for key, val in VALUES.items():
        text = text.replace("{{" + key + "}}", val)
    # Catch any leftover placeholder so we never publish a raw {{...}}.
    leftover = re.findall(r"\{\{[^}]+\}\}", text)
    if leftover:
        raise SystemExit(f"Unfilled placeholders: {sorted(set(leftover))}")
    return text


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    md = markdown.Markdown(extensions=["tables", "sane_lists", "attr_list"])
    for src, (out_name, title) in PAGES.items():
        raw = (SRC / src).read_text(encoding="utf-8")
        body = md.reset().convert(fill(raw))
        html = SHELL.format(title=title, body=body, year=date.today().year)
        (OUT / out_name).write_text(html, encoding="utf-8")
        print(f"wrote {out_name} ({len(html)} bytes)")
    # NB: index.html (the landing page) is intentionally NOT written here — it is a
    # hand-maintained static site under deploy/site/.


if __name__ == "__main__":
    main()
