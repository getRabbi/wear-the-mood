# Feature graphic design brief — Wear The Mood (`com.fashionos.app`)

Brief for the Play Store **feature graphic** — the 1024×500 banner shown at the top
of the listing and used when Google features the app. Docs only — no code changes.
Pair with `APP_ICON_BRIEF.md` + `PLAY_STORE_SCREENSHOTS.md` so the icon, banner, and
screenshots read as one set.

**Look:** same "AI fashion-tech / dark luxury" system — deep plum, violet→pink
gradient, lavender highlights. Premium, editorial, confident.

---

## Specs (hard requirements)
- **Size:** exactly **1024 × 500 px**.
- **Format:** PNG or JPG, **RGB, NO alpha/transparency**, ≤ 15 MB (aim ≤ 1 MB).
- **Margins:** keep all text/logo ≥ **64 px** from every edge (Play crops/scales it across surfaces).
- **Center-safe:** if you ever add a promo video, Play overlays a **play button in the center** — keep the middle ~300×300 px free of critical text/faces.
- **Don't rely on text alone:** the app name + icon are shown separately; the graphic must still look good if text is partly obscured.

## Brand colors (from the app theme — same as the icon)
- Plum field: `#0E0B14` / rich `#160B26 → #2A1A47`
- **Signature gradient:** violet → pink, `#8B35FF → #F43F7F` (optional magenta 3rd stop `#FF49C6`)
- Lavender highlight `#C084FC` · muted-lavender text `#B9AFC8` · white `#FFFFFF`

---

## Layout directions (pick one; #1 recommended)
**1. Text-left / hero-right (recommended)**
- Left: wordmark **"Wear The Mood"** (large display/Fraunces, white) + one-line hook **"See any outfit on you"** (lavender).
- Right: a single styled try-on figure **or** a clean 2–3 phone-mockup cluster (try-on → closet), with a soft violet→pink glow.
- Background: plum with the signature gradient sweeping from lower-left.
- Keeps the center workable for a future video overlay.

**2. Centered brand statement (minimal)**
- Big centered **"Wear The Mood"** on the violet→pink-over-plum gradient with a subtle garment/monogram motif. Elegant but **conflicts with the center play-button overlay** if you add a video — only use if no promo video is planned.

**3. Three-up showcase**
- A row of three device screens (try-on, closet, community) under the name + hook band. Communicates breadth; busier, so keep type large.

---

## Content
- **Wordmark:** Wear The Mood
- **Hook (one line, optional but recommended):** "See any outfit on you" (or "Your AI closet, stylist & style feed")
- **Visual:** styled figure or app mockups — use **demo content only** (no real selfies, names, or faces you don't have rights to).
- Optional small **monogram "W"** mark (from the icon) for cohesion.

## Do / Don't
- ✅ Large, high-contrast type; consistent gradient + plum with the icon/screenshots.
- ✅ Demo data only; tasteful glow; generous margins.
- ❌ No "perfect fit", AR, medical, or guaranteed-photoreal claims.
- ❌ No tiny text, no edge-to-edge text, nothing critical dead-center.
- ❌ No transparency, no off-brand colors, no stocky/cluttered collage.

## Export checklist
- [ ] `feature_graphic` — **1024×500** PNG/JPG, RGB, no alpha, ≤ 1 MB.
- [ ] Same gradient/plum + type as the **icon** and **screenshot caption band** (one visual system).
- [ ] Previewed small (it renders narrow on phones) — wordmark still legible.
- [ ] Source file (Figma/SVG/PSD) kept for edits.
