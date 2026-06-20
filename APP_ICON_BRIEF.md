# App icon design brief — Wear The Mood (`com.fashionos.app`)

Brief for a designer (or AI generator) to produce the Play Store icon + the Android
adaptive launcher icon. Docs only — no code changes.

**Look:** "AI fashion-tech / dark luxury" — deep plum backgrounds, purple→pink
gradients, muted-lavender highlights. Premium, editorial, minimal. The icon must
read instantly at small sizes and feel like a fashion app, not a camera/photo app.

---

## Brand colors (exact, from the app theme `tokens.dart`)
| Role | Hex |
|---|---|
| Page background (deepest plum) | `#0E0B14` |
| Premium plum (rich bg option) | `#160B26` → `#2A1A47` |
| **Primary pink (accent)** | `#F43F7F` |
| **Electric violet (secondary)** | `#8B35FF` |
| Lavender (highlight) | `#C084FC` |
| Hot magenta edge | `#FF49C6` |
| Muted-lavender text | `#B9AFC8` |

**Signature gradient (use this):** violet → pink, `#8B35FF → #F43F7F`
(optional 3-stop with magenta: `#8B35FF → #F43F7F → #FF49C6`), on a `#0E0B14`/`#160B26` plum field.

---

## Deliverables
1. **Play Store icon** — 512×512 px, 32-bit PNG (alpha allowed), ≤1 MB. The full composed mark + plum/gradient background. (Play applies its own rounded mask — keep the mark centered, nothing critical in the corners.)
2. **Android adaptive launcher icon** — two layers, each full-bleed **432×432 px** (108dp @ xxxhdpi):
   - **Foreground:** the mark on transparency.
   - **Background:** the plum/gradient field, fully opaque.
   - **Safe zone:** keep all essential art inside the **central 264×264 px (66dp) circle** — the outer ~18dp per side can be clipped by circle / squircle / rounded-square masks.
3. Source file (SVG or layered PNG/Figma) for future edits.

---

## Concept directions (pick one; #1 recommended)
**1. Monogram "W" (recommended)** — a refined custom **W** (or interlocking W+M) in white→lavender on the violet→pink gradient over plum. Cleanest tie to "Wear The Mood", premium, legible at 48 px.

**2. Garment / hanger glyph** — a single minimal clothes-hanger or draped-garment silhouette drawn as one gradient stroke. More literally "fashion/closet"; still simple.

**3. Mood orb + fold** — an abstract gradient orb with one fashion cue (a fabric fold or a needle-and-thread arc). Modern, but less specific to the brand — use only if you want fully abstract.

> Avoid a face/portrait or a literal mirror — it reads as a selfie/camera app and muddies the fashion positioning.

---

## Do / Don't
- ✅ One strong, centered silhouette; high contrast; recognizable on a busy home screen.
- ✅ Use the signature gradient + plum; keep it consistent with the in-app brand.
- ✅ Test legibility at **48 px** and on both light and dark wallpapers (adaptive).
- ❌ **No text/wordmark** in the icon (illegible small; the listing shows the name).
- ❌ No photos, no faces, no fine detail, no drop-shadows that vanish at small sizes.
- ❌ Don't fill the corners (Play + launcher masks crop them).
- ❌ No "perfect fit", AR, or photoreal claims implied by the art.

---

## Export checklist
- [ ] `ic_launcher` Play icon — **512×512** PNG (≤1 MB).
- [ ] Adaptive **foreground** — 432×432 PNG (transparent), mark in the central 264 px.
- [ ] Adaptive **background** — 432×432 PNG (opaque plum/gradient).
- [ ] (Optional) monochrome layer for Android 13+ themed icons — 432×432, single-color on transparent.
- [ ] Source (SVG / Figma / layered PSD).
- [ ] Quick check: drop the 512 into Android Studio **Image Asset Studio** to preview circle/squircle/rounded masks before finalizing.
