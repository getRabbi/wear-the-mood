# WEAR THE MOOD — UI Implementation Spec (Atelier Edition)
**For Claude Code · Flutter app · v1.0 LOCKED**

> Source of truth for visuals: `design/wear-the-mood-ui.html` (13-screen board).
> Read that file FIRST. Every color, radius, spacing, and type decision below is extracted from it.
> This document adds the screens the board does NOT show, locks all placement decisions, and defines the phase-gated build order.

---

## 0. GROUND RULES (non-negotiable)

1. **Do not touch the backend.** FastAPI endpoints, Supabase schema, R2 buckets, signed-URL services, Real-ESRGAN pipeline, FASHN credit logic, RevenueCat products — all exist and work. This is a UI implementation on top of existing services.
2. **Detect and conform.** Inspect the existing Flutter codebase for state management, routing, and service layer patterns. Follow whatever is there. Do not introduce a new state management library.
3. **One phase at a time.** Complete the phase, run it, then STOP and wait for review. Never continue into the next phase unprompted.
4. **Every screen ships with 4 states:** content, loading (shimmer on fabric-swatch placeholder), empty (invitation to act, never mood-only), error (what happened + retry).
5. **No new heavy dependencies.** Allowed additions: bundled font TTFs (assets), `shimmer` or hand-rolled equivalent. Nothing else without approval.
6. **Fonts are bundled, not fetched.** Download Cormorant Garamond (400/500/600 + italics) and Outfit (300/400/500/600) TTFs into `assets/fonts/`, declare in pubspec. No runtime Google Fonts fetch (offline + review safety).

---

## 1. DESIGN TOKENS (extract into `lib/theme/`)

### 1.1 Colors — `wtm_colors.dart`
| Token | Value | Use |
|---|---|---|
| `bg` | `#08060F` | Scaffold background |
| `bg2` | `#0D0A18` | Frame/gradient top |
| `panel` | `#100C1D` | Sheets, dialogs |
| `line` | `Colors.white @ 8%` | Card borders |
| `lineSoft` | `Colors.white @ 5.5%` | Dividers, nav border |
| `gold` | `#D9BE95` | Accent, active states, headings accent |
| `gold2` | `#B99A6B` | Slider fill gradient start |
| `goldDim` | `#D9BE95 @ 55%` | Eyebrow labels |
| `text` | `#EFEAF6` | Primary text |
| `muted` | `#E7E1F3 @ 56%` | Secondary text |
| `faint` | `#E7E1F3 @ 34%` | Micro text, inactive nav |
| `orchid` | `#C98BFF` | CTA gradient mid |
| `violet` | `#8E7BFF` | CTA gradient start |
| `pinkish` | `#F3B9E2` | CTA gradient end |
| `ctaText` | `#241243` | Text on gradient CTA |

Card fill: `LinearGradient(165°, white@4.5% → white@1.2%)`.
Aurora recipe (backgrounds/imagery placeholders): 3 stacked radial gradients — violet `rgba(190,120,255,.34)` top-right, pink `rgba(243,150,205,.18)` bottom-left, plum `rgba(96,62,168,.42)` center — over `linear(162°, #191129 → #0A0614)` + grain overlay (noise PNG asset, `BlendMode.overlay`, opacity .09).

### 1.2 Type — `wtm_typography.dart`
| Role | Face | Size/weight | Notes |
|---|---|---|---|
| Display | Cormorant Garamond 500 | 28 | Home greeting; italic+gold for the emphasized word |
| H1 screen title | Cormorant Garamond 500 | 22 | |
| H2 card title | Cormorant Garamond 500 | 17–20 | |
| Body | Outfit 300 | 12.5 | line-height 1.5 |
| Label | Outfit 400–500 | 12.5 | buttons, row titles |
| Eyebrow | Outfit 500 | 9, tracking .30em, UPPERCASE, goldDim | section markers |
| Micro | Outfit 300 | 10, faint | metadata |

### 1.3 Shape & spacing
Radii: card 18 · tile 12 · button 15 · chip 999 · sheet top 26 · **arch portal `BorderRadius.vertical(top: Radius.circular(158))`**.
Spacing scale: 4/6/8/10/12/14/16/18/22. Screen padding: 18 horizontal.
Fabric-swatch placeholder colorways c1–c8 (used as image loading placeholders + empty tiles): noir `#332C3E→#15101C`, ivory `#EBDFCB→#C4B092`, plum `#714C93→#3A2458`, orchid `#C46BC0→#7C3A8E`, bronze `#8D6D40→#4C3A1E`, wine `#823452→#48192F`, slate `#4C5069→#22253A`, blush `#DBACBB→#9A6377`, each with diagonal sheen `linear(118°, transparent 32% → white@17% 46% → transparent 58%)`.

---

## 2. NAVIGATION ARCHITECTURE — LOCKED

**Bottom nav (persistent, 5 slots):** `Home · Social · [ORB] · Inbox · Profile`

- **ORB tap → Upload Hub as modal bottom sheet** (board screen 13). The orb is the app's "+". Sheet entries route to: Add Garment flow, Body Photo flow, Save a Look, Brand/Store, **Try It On → MoodMirror Step 1**.
- Home quick action "Try-On Studio" → MoodMirror Step 1 directly.
- **Giveaways / Offers / Newsroom are NOT nav tabs.** They live as a "Discover" horizontal card row on Home (below Inspiration) and each opens as a sub-page (board screens 08/09/10). Their updates also appear in Inbox → Drops tab.
- Orb animation: breathing glow, 4.5s ease-in-out loop (scale shadow only, not size). Respect reduced-motion.

**MoodMirror flow order — LOCKED:**
`Step 1 body photo → Step 2 garments → Step 3 mode+credits → GENERATING → RESULT → (optional) Adjust editor → Save to Looks`.
Board screen 06 (editor) comes AFTER result, entered via "Adjust" on the result screen. Back from editor returns to result with edits applied.

---

## 3. GAP ANALYSIS — 19 screens the board does not show

Build these in the same design language. Placement locked as stated. **Nothing outside this list + §3.1 amendments + §8 matrix exists in v1 scope — and everything inside it MUST ship.**

### A. Auth & Onboarding
1. **Splash** — centered orb (large, breathing) + serif wordmark + tagline micro. Auto-routes by session.
2. **Sign In / Sign Up** — Apple + Google + email (Supabase auth). Apple Sign-In is mandatory on iOS because Google login exists. Aurora background, gradient CTA for primary, ghost for secondary, legal micro-links at bottom.
3. **Onboarding (3 steps)** — mood baseline slider, style tags (chips → seeds Style DNA), body-photo primer (arch portal illustration, "add later" allowed). Skippable except account.

### B. Try-On core (highest priority gap)
4. **Generating screen** — full-bleed aurora, large orb center, rotating status copy ("Draping the silhouette…", "Matching light and shadow…"), thin gold progress line, Cancel ghost. Poll existing job endpoint; on the known completion-signal/CDN edge case, retry fetch with backoff before erroring (mirrors the fixed background-removal pattern).
5. **Result screen** — full-bleed try-on image, top overlay: back + credits pill; bottom action bar: `Save Look` (gradient CTA) · `Adjust` (→ screen 06 editor) · `Retry` · `Share`. Low-res first, swap to Real-ESRGAN upscaled when ready (existing caching pipeline).
6. **Saved Looks gallery** — grid of generated looks; lives as Profile segment 2 (see §4). Tile tap → result screen in "view" mode.

### C. Monetization
7. **Paywall** — triggered by: any PRO badge tap (screen 05 modes), Generate with insufficient tier, credits row "Get more", Settings → Subscription. Layout: serif headline, 3 tier cards (Free / **Pro $8.99** / **Pro Max $15.99**) styled like `modecard` with gold `on` state, benefit micro-rows (FASHN credits/month, AI Couture, Full Look, priority queue), gradient CTA `Continue`, then **Restore Purchases** ghost + terms micro (both required for App Store). RevenueCat — reuse existing product IDs, do not create new ones.
8. **Credit top-up sheet** — bottom sheet, 3 pack cards + current balance (coin icon + serif number, matches screen 05 credits row). Entry: credits row tap, low-credit interstitial before Generate.

### D. Closet depth
9. **Garment detail** — hero image (3:4, R2 signed URL), category + tags chips, wear stats micro, actions: `Try It On` (gradient CTA) · Edit · Delete (confirm dialog). Entry: any closet tile.
10. **Add Garment flow** — camera/gallery → **background removal progress** (aurora card + gold progress, uses existing pipeline with the fixed completion handling) → preview on noir tile → category/tags confirm → saved toast "Added to closet". Entry: Upload Hub, Closet empty state, Closet header +.

### E. Social depth (feature-flag `community_enabled`)
11. **Post detail** — full post + comments list + composer.
12. **Create Post** — pick from Looks/Closet → caption → tags → publish (goes through existing moderation/shadowban backend).
13. **Public profile** — other users: avatar, stats, posts grid, Follow pill. Includes **Followers / Following list screens** (row = AvatarRing + name + follow pill), reachable from stat taps on both own (11) and public profiles.
14. **Report / Block sheet** — from the `⋯` menu on every post and profile. Reasons list → submits to existing admin/moderation endpoints; Block hides user content locally immediately. **App Store hard requirement for UGC** — see §6.

### F. System
15. **Inbox** — tabs: `Activity` (likes/follows/comments) · `Drops` (giveaways/offers/news digests) · `System` (credits, subscription, moderation notices). Row style = settings row with ricon.
16. **Search** — from Home/Closet/Community search icons; scoped tabs: Closet · Community · Brands. Debounced, recent searches chips.
17. **Discover details trio** — Giveaway detail (hero, prize value, countdown, `Enter Now` → entered state pill, rules micro), Offer detail (brand mark, code copy pill, `Shop Now` external), Newsroom article reader (serif long-form, drop cap optional, 62ch measure).

### G. Styling intelligence (⚠ board screen 01 shows these as quick actions — without them, two Home buttons dead-end)
18. **AI Stylist** — the "Atelier Assistant". Entry: Home quick action, orb-sheet assistant card (13), Today's Look card tap. Layout: aurora header with mini orb + serif greeting, mood/weather context chips (reads Home mood slider value + 22°C-style weather line), then suggested **LookCards** (name like "Moonlit Confidence", garment mini-row from user's real closet, `Try This On` gradient CTA → pre-fills MoodMirror Step 2, `Shuffle` ghost). Look detail view = expanded LookCard + reasoning micro ("AI insight — …" same pattern as Style DNA). Uses existing backend suggestion/credit rules; if no closet items → EmptyState routing to Add Garment.
19. **Outfit Maker** — manual outfit composer. Entry: Home quick action, Closet "Outfits" stat tap, Upload Hub "Save a Look". Layout: slot canvas (Top / Bottom / Layer / Extra as dashed noir tiles) + closet picker strip below (FabricTiles, tap to fill slot), name field (serif), `Save Outfit` gradient CTA. Saved outfits list grid precedes the composer (28-outfit stat maps here); outfit tap → detail with `Try It On` (→ MoodMirror Step 2 pre-filled) and Edit/Delete.

### Screen amendments (board screens, add these elements)
- **11 Profile:** segmented control `Closet · Looks · Posts` above grid; Edit Profile pill under name.
- **12 Settings — append rows:** `Subscription` (plan, manage, **Restore Purchases**) · `Legal` (Privacy Policy, Terms) · **`Delete Account`** (danger, double-confirm — App Store requirement) · `Sign Out` · version micro at bottom.
- **01 Home:** add Discover row (3 entry cards → 08/09/10) below Inspiration; bell → Inbox; mood slider persists to profile and re-seeds Today's Look + AI Stylist context.
- **02 Closet:** stat cells are tap targets — Items→All, Outfits→19 list, Favorites→favorites filter, Categories→category sheet.
- **05 Step 3:** insufficient credits → inline warning + `Get credits` pill (→ top-up sheet), Generate disabled state.
- **07 Community:** bookmark toggles Saved; Saved posts list lives under Profile `⋯` menu. "Near You" tab requires location permission (graceful fallback to For You if denied).
- **09 Garment detail (new):** heart toggle feeds the closet Favorites stat/filter.

---

## 4. COMPONENT LIBRARY — `lib/ui/widgets/` (build once, reuse everywhere)

`WtmScaffold` (bg + optional aurora) · `AuroraBox` · `GrainOverlay` · `TheOrb(size, breathing)` · `WtmBottomNav` (orb floats −20, gold active) · `GradientCta(icon?, label)` · `GhostButton` · `GoldPill` · `WtmChip / ChipRow` · `FabricTile` (network image, shimmer→swatch placeholder c1–c8 rotation, optional sel/add badge) · `ArchPortal` · `ModeCard(thumb, title, sub, badge, on)` · `Badge.free / Badge.pro` · `CreditsRow` · `AdjustSlider(label, value)` · `StatGrid(4)` · `SettingsRow(icon, title, sub)` · `EyebrowLabel` · `AvatarRing` · `MemberCard` · `EmptyState(icon, title, sub, cta)` · `PostCard` · `LookCard(name, garmentMinis, cta)` · `OutfitSlot(label, garment?)` · `SegmentedControl`.

Icon set: replicate the HTML's 1.5-stroke rounded icon style — use `lucide_icons` if already in the project, otherwise a small custom `CustomPainter`/SVG asset set copied from the board's symbols.

---

## 5. PHASE PLAN — execute strictly in order, STOP after each

| Phase | Scope | Gate (must show before continuing) |
|---|---|---|
| **P0** | Theme: colors, typography (bundled fonts), radii, `WtmScaffold`, `AuroraBox`, `GrainOverlay`, `TheOrb`, `GradientCta`, `WtmChip`, `FabricTile` | Component gallery screen, side-by-side faithful to HTML board |
| **P1** | Nav shell: 5-tab scaffold, orb → Upload Hub sheet, **route table covering every §8 destination (stubs)** | Tap-through: zero dead ends |
| **P2** | Home (board 01 + Discover row + bell→Inbox + mood persistence) | Home pixel pass |
| **P3** | Closet (02 + stat taps + favorites) + Garment detail + Add Garment flow (bg-removal wired) | Add→remove-bg→save→appears in grid, real R2 URLs |
| **P4** | MoodMirror 1–3 (03/04/05) + Generating + Result + Editor (06), credits read, upscale swap | Full try-on happy path on device + error path |
| **P5** | **AI Stylist (18) + Outfit Maker (19)** + Today's Look wiring + MoodMirror pre-fill handoff | Suggest→Try This On lands in Step 2 pre-filled |
| **P6** | Paywall + Credit top-up (RevenueCat sandbox) | Purchase + restore both verified in sandbox |
| **P7** | Profile (11 + segments + Looks gallery + follow lists) + Settings (12 + compliance rows incl. Delete Account) | Delete-account flow demo |
| **P8** | Community (07 + detail + create + public profile + report/block), behind `community_enabled` flag | Report reaches admin panel; block hides content |
| **P9** | Inbox + Giveaways/Offers/Newsroom (08/09/10) + detail trio + Search (16) | Deep links from Inbox Drops work |
| **P10** | Auth/Onboarding + all empty/error/offline states + release QA (§6) + §8 full audit | Checklist all green, matrix all green |

Per-phase prompt to use in Claude Code:
> "Read `design/wear-the-mood-ui.html` and `UI_IMPLEMENTATION.md`. Execute **Phase N only**, following §0 ground rules. When done: list files changed, how to run, and what to verify. STOP."

---

## 6. RELEASE / APP STORE CHECKLIST (P9 gate — launch blockers)

- [ ] Sign in with Apple present (Google login exists → mandatory)
- [ ] **Account deletion in-app** (Settings) — hard requirement
- [ ] **UGC compliance:** report content + block user + moderation contact + guidelines link (admin panel already handles backend) — hard requirement if Community ships; otherwise keep `community_enabled=false` for iOS v1
- [ ] Restore Purchases visible on paywall; subscription price, period, and terms text on paywall
- [ ] Privacy Policy + Terms reachable from Settings and paywall
- [ ] Privacy nutrition labels match actual collection (photos, purchases, identifiers)
- [ ] Try-on photos: camera/photos permission strings written in plain language
- [ ] Offline: closet browsable from cache, clear retry on generate
- [ ] Reduced-motion: orb static, no aurora animation
- [ ] Location permission string ("Near You" feed) + graceful denial fallback
- [ ] **§8 tap-target matrix 100% green — every visible element routes somewhere real (no dead ends)**

---

## 7. REPO SETUP (do this before P0)

```
app/
├── design/
│   └── wear-the-mood-ui.html      ← the approved board (source of truth)
├── UI_IMPLEMENTATION.md            ← this file
├── assets/fonts/                   ← CormorantGaramond-*.ttf, Outfit-*.ttf
└── assets/textures/grain.png       ← 140px noise tile
```

---

## 8. TAP-TARGET COVERAGE MATRIX — the "no feature left behind" contract

Every visible interactive element on the 13-screen board, mapped to a real destination. Claude Code must verify this table at P1 (stubs) and P10 (final). If an element is not in this table, it does not exist; if it is, it must work.

| Board screen | Element | Destination |
|---|---|---|
| Nav (all) | Home / Social / Inbox / Profile | Tabs 01 / 07 / 15-Inbox / 11 |
| Nav (all) | **Orb** | Upload Hub sheet (13) |
| 01 Home | Bell | Inbox (15) |
| 01 Home | Mood slider | Persists mood → reseeds Today's Look + Stylist |
| 01 Home | Try-On Studio | MoodMirror Step 1 (03) |
| 01 Home | Smart Closet | Closet (02) |
| 01 Home | AI Stylist | Stylist (18) |
| 01 Home | Outfit Maker | Outfit Maker (19) |
| 01 Home | Today's Look card | Stylist look detail (18) |
| 01 Home | Inspiration tiles / View all | Post detail (11-E) / Community For You |
| 01 Home | Discover row (added) | Giveaways 08 / Offers 09 / Newsroom 10 |
| 02 Closet | Search icon | Search (16, closet scope) |
| 02 Closet | Stat cells | Items→All · Outfits→19 · Favorites→filter · Categories→sheet |
| 02 Closet | Filter chips + funnel | Filter grid / filter sheet |
| 02 Closet | Garment tile | Garment detail (9) |
| 03 Step 1 | Back | Previous |
| 03 Step 1 | Upload Photo / Select Gallery | Camera / picker → crop → set body photo |
| 03 Step 1 | Portal (photo exists) | Body photo manager |
| 04 Step 2 | Tile +/✓ | Toggle selection |
| 04 Step 2 | Next · Choose Mode | Step 3 (05) |
| 05 Step 3 | Mode cards | Select (gold `on` state) |
| 05 Step 3 | PRO badge on locked tier | Paywall (7) |
| 05 Step 3 | Credits row | Top-up sheet (8) |
| 05 Step 3 | Generate Look | Generating (4) → Result (5); insufficient → top-up interstitial |
| 06 Editor | Rail tools / sliders / Reset | Local edit state |
| 06 Editor | Done | Back to Result with edits |
| Result (5) | Save / Adjust / Retry / Share | Looks gallery / 06 / 05 / OS share |
| 07 Community | Search | Search (16, community scope) |
| 07 Community | Tabs incl. Near You | Feeds (Near You gated by location perm) |
| 07 Community | Avatar / name | Public profile (13) |
| 07 Community | `⋯` | Report / Block sheet (14) |
| 07 Community | Post image / comment | Post detail (11-E) |
| 07 Community | Heart / Bookmark | Like toggle / Saved (Profile `⋯` → Saved posts) |
| 08 Giveaways | Enter Now / cards / View all | Giveaway detail (17) with entered state / full list |
| 09 Offers | Shop Now / card | Offer detail (17) → external link |
| 10 Newsroom | Read More / story tiles / View all | Article reader (17) / stories list |
| 11 Profile | Edit Profile pill (added) | Edit profile form |
| 11 Profile | Stat cells | Followers/Following lists (13) · Items→Closet · Outfits→19 |
| 11 Profile | Segments (added) | Closet / Looks (6) / Posts |
| 11 Profile | Closet minis / View all | Garment detail (9) / Closet |
| 11 Profile | Member card | Subscription manage / Paywall (7) |
| 12 Settings | 6 rows + added rows | Account / Prefs / Notifications / Privacy / Units / Help / **Subscription** / **Legal** / **Delete Account** / **Sign Out** |
| 12 Settings | Body photo Update | Body photo flow (03-style) |
| 13 Upload Hub | 5 rows | Add Garment (10) / Body photo / Outfit Maker (19) / Brand-Store form / MoodMirror Step 1 |
| 13 Upload Hub | Atelier Assistant card | AI Stylist (18) |

**Final count: 13 board screens + 19 gap screens (§3) + amendments (§3.1) = complete v1 surface. 11 phases (P0–P10), each gated.**
