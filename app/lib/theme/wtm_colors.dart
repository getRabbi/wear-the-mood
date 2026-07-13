import 'package:flutter/material.dart';

/// Wear The Mood — Atelier Edition color tokens (UI_IMPLEMENTATION.md §1.1).
/// Extracted 1:1 from `app/design/wear-the-mood-ui.html` (the approved board).
/// The ONLY place raw WTM color values live — never hardcode colors in widgets.
///
/// Alpha channels are the board's CSS rgba() percentages converted to 0–255
/// (e.g. white @ 8% → 0x14). Comments carry the original CSS for traceability.
abstract final class WtmColors {
  // ---- Core palette (§1.1 table) ----
  static const bg = Color(0xFF08060F); // scaffold background
  static const bg2 = Color(0xFF0D0A18); // frame/gradient top
  static const panel = Color(0xFF100C1D); // sheets, dialogs
  static const line = Color(0x14FFFFFF); // white @ 8% — card borders
  static const lineSoft = Color(0x0EFFFFFF); // white @ 5.5% — dividers, nav
  static const gold = Color(0xFFD9BE95); // accent, active states
  static const gold2 = Color(0xFFB99A6B); // slider fill gradient start
  static const goldDim = Color(0x8CD9BE95); // gold @ 55% — eyebrow labels
  static const text = Color(0xFFEFEAF6); // primary text
  static const muted = Color(0x8FE7E1F3); // #E7E1F3 @ 56% — secondary text
  static const faint = Color(0x57E7E1F3); // #E7E1F3 @ 34% — micro, inactive nav
  static const orchid = Color(0xFFC98BFF); // CTA gradient mid
  static const violet = Color(0xFF8E7BFF); // CTA gradient start
  static const pinkish = Color(0xFFF3B9E2); // CTA gradient end
  static const ctaText = Color(0xFF241243); // text on gradient CTA

  // ---- Fills & borders (board CSS) ----
  static const cardFillTop = Color(0x0BFFFFFF); // white @ 4.5% (.card)
  static const cardFillBottom = Color(0x03FFFFFF); // white @ 1.2% (.card)
  static const tileBorder = Color(0x12FFFFFF); // white @ 7% (.tile/.ed)
  static const chipBg = Color(0x04FFFFFF); // white @ 1.5% (.chip)
  static const chipOnBg = Color(0x17D9BE95); // gold @ 9% (.chip.on)
  static const chipOnBorder = Color(0x80D9BE95); // gold @ 50% (.chip.on)
  static const ghostBg = Color(0x06FFFFFF); // white @ 2.5% (.ghost)
  static const pillBorder = Color(0x73D9BE95); // gold @ 45% (.pill)
  static const pillBg = Color(0x0FD9BE95); // gold @ 6% (.pill)
  static const ctaInnerHighlight = Color(0x59FFFFFF); // inset 0 1px white @ 35%
  static const ctaGlow = Color(0x8CA06EFF); // rgba(160,110,255,.55) (.cta)
  static const scaffoldGlow = Color(0x2E8C5FDC); // rgba(140,95,220,.18) top glow
  static const vignette = Color(0x8C05030A); // rgba(5,3,10,.55) (.vig)

  // ---- Aurora recipe (§1.1 — backgrounds / imagery placeholders) ----
  static const auroraBaseTop = Color(0xFF191129); // linear(162°) start
  static const auroraBaseBottom = Color(0xFF0A0614); // linear(162°) end
  static const auroraViolet = Color(0x57BE78FF); // rgba(190,120,255,.34) top-right
  static const auroraPink = Color(0x2EF396CD); // rgba(243,150,205,.18) bottom-left
  static const auroraPlum = Color(0x6B603EA8); // rgba(96,62,168,.42) center

  // Blush aurora variant (board's alternating editorial tiles — e.g. Home
  // inspiration tile 2): pink-led glows over a warmer #1B1230 base.
  static const auroraBaseTop2 = Color(0xFF1B1230);
  static const auroraPinkStrong = Color(0x4DF396CD); // rgba(243,150,205,.3)
  static const auroraVioletStrong = Color(0x668C5FDC); // rgba(140,95,220,.4)

  // ---- The Orb (board .orb) ----
  static const orbCore1 = Color(0xFFF2E4FF); // radial 0%
  static const orbCore2 = Color(0xFFC89BFF); // radial 32%
  static const orbCore3 = Color(0xFF8A63E8); // radial 58%
  static const orbCore4 = Color(0xFF3D2578); // radial 82%
  static const orbCore5 = Color(0xFF1E1240); // radial 100%
  static const orbRing = Color(0x59C896FF); // rgba(200,150,255,.35) outer ring
  static const orbGlowInner = Color(0x99A06EFF); // rgba(160,110,255,.6)
  static const orbGlowInnerPeak = Color(0xBFAA78FF); // rgba(170,120,255,.75)
  static const orbGlowOuter = Color(0x99BE82FF); // rgba(190,130,255,.6)
  static const orbGlowOuterPeak = Color(0xBFC88CFF); // rgba(200,140,255,.75)
  static const orbInsetShadow = Color(0xB3140832); // inset rgba(20,8,50,.7)
  static const orbSheen = Color(0x80FFFFFF); // inset top white @ 50%
  static const orbHighlight = Color(0xD9FFFFFF); // white @ 85% blurred blob

  // ---- Tile badges (board .sel / .addring) ----
  static const selBadgeShadow = Color(0x808C5AFF); // rgba(140,90,255,.5)
  static const addRingBorder = Color(0x66FFFFFF); // white @ 40%
  static const addRingBg = Color(0x590A0712); // rgba(10,7,18,.35)
  static const addRingIcon = Color(0xBFFFFFFF); // white @ 75%

  // ---- Fabric swatch treatment (§1.3) ----
  static const swatchShade = Color(0x61000000); // black @ 38% (.tile::before)
  static const sheenWhite = Color(0x2BFFFFFF); // white @ 17% (.tile::after)

  // ---- List rows (board .row — settings/upload hub) ----
  static const rowFillTop = Color(0x09FFFFFF); // white @ 3.5%
  static const rowFillBottom = Color(0x02FFFFFF); // white @ 0.8%
  static const riconBorder = Color(0x47D9BE95); // gold @ 28% (.ricon)
  static const riconBg = Color(0x0DD9BE95); // gold @ 5% (.ricon)

  // ---- Icon button (board .iconbtn) ----
  static const iconBtnBg = Color(0x05FFFFFF); // white @ 2%

  // ---- Bottom nav (board .navbar) ----
  static const navTop = Color(0x660D0A18); // rgba(13,10,24,.4)
  static const navBottom = Color(0xEB090611); // rgba(9,6,17,.92)

  // ---- Atelier assistant card (board .assist) ----
  static const assistBorder = Color(0x59A06EFF); // rgba(160,110,255,.35)
  static const assistFillTop = Color(0x268C5FDC); // rgba(140,95,220,.15)
  static const assistFillBottom = Color(0x088C5FDC); // rgba(140,95,220,.03)
  static const assistEyebrow = Color(0xCCC89BFF); // rgba(200,155,255,.8)

  // ---- Tier badges (board .badge.free / .badge.pro) ----
  static const badgeFreeText = Color(0xFF0E2B1E);
  static const badgeFreeStart = Color(0xFFB9E3C6);
  static const badgeFreeEnd = Color(0xFF8FCBA8);
  static const badgeProStart = Color(0xFFE3C892);
  static const badgeProEnd = gold; // #D9BE95
  // .badge.pro text is the CTA plum (ctaText).
  // Pro Max — the strongest tier: the signature violet→orchid premium gradient
  // (distinct from Pro's gold) with light text.
  static const badgeProMaxStart = Color(0xFF8C5FDC); // violet (assist family)
  static const badgeProMaxEnd = Color(0xFFC77DFF); // orchid (mood spectrum)
  static const badgeProMaxText = Color(0xFFFDFBFF);

  /// System danger (destructive rows/dialogs). Not on the board — carried from
  /// the app-wide status palette (CLAUDE.md §4.1) for Delete Account etc.
  static const danger = Color(0xFFB23B3B);
}

/// WTM gradient recipes (§1.1). CSS `linear-gradient(θ)` angles are converted
/// to begin/end alignments via the unit direction (sin θ, −cos θ·(y-down));
/// each gradient notes its source angle.
abstract final class WtmGradients {
  /// Card fill — `linear(165°, white@4.5% → white@1.2%)`.
  static const cardFill = LinearGradient(
    begin: Alignment(-0.259, -0.966),
    end: Alignment(0.259, 0.966),
    colors: [WtmColors.cardFillTop, WtmColors.cardFillBottom],
  );

  /// Gradient CTA — `linear(95°, violet 0% → orchid 48% → pinkish 100%)`.
  static const cta = LinearGradient(
    begin: Alignment(-0.996, -0.087),
    end: Alignment(0.996, 0.087),
    colors: [WtmColors.violet, WtmColors.orchid, WtmColors.pinkish],
    stops: [0.0, 0.48, 1.0],
  );

  /// Aurora base — `linear(162°, #191129 → #0A0614)`.
  static const auroraBase = LinearGradient(
    begin: Alignment(-0.309, -0.951),
    end: Alignment(0.309, 0.951),
    colors: [WtmColors.auroraBaseTop, WtmColors.auroraBaseBottom],
  );

  /// Diagonal fabric sheen — `linear(118°, transparent 32% → white@17% 46% →
  /// transparent 58%)` (§1.3).
  static const sheen = LinearGradient(
    begin: Alignment(-0.883, -0.469),
    end: Alignment(0.883, 0.469),
    colors: [Color(0x00FFFFFF), WtmColors.sheenWhite, Color(0x00FFFFFF)],
    stops: [0.32, 0.46, 0.58],
  );

  /// Selected-tile badge — `linear(140°, orchid → violet)` (board .sel).
  static const selBadge = LinearGradient(
    begin: Alignment(-0.643, -0.766),
    end: Alignment(0.643, 0.766),
    colors: [WtmColors.orchid, WtmColors.violet],
  );

  /// Gold slider fill — `linear(90°, gold2 → gold)`.
  static const sliderFill = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [WtmColors.gold2, WtmColors.gold],
  );

  /// Scaffold base — bg2 (frame/gradient top, §1.1) into bg.
  static const scaffoldBase = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [WtmColors.bg2, WtmColors.bg],
  );

  /// List-row fill (board `.row`) — `linear(165°, white@3.5% → white@0.8%)`.
  static const rowFill = LinearGradient(
    begin: Alignment(-0.259, -0.966),
    end: Alignment(0.259, 0.966),
    colors: [WtmColors.rowFillTop, WtmColors.rowFillBottom],
  );

  /// Bottom-nav wash (board `.navbar`) — `linear(180°, rgba(13,10,24,.4) →
  /// rgba(9,6,17,.92))`.
  static const navFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [WtmColors.navTop, WtmColors.navBottom],
  );

  /// Atelier-assistant card fill (board `.assist`) — `linear(140°,
  /// rgba(140,95,220,.15) → rgba(140,95,220,.03))`.
  static const assistFill = LinearGradient(
    begin: Alignment(-0.643, -0.766),
    end: Alignment(0.643, 0.766),
    colors: [WtmColors.assistFillTop, WtmColors.assistFillBottom],
  );

  // ---- Radial recipes ----
  // CSS `radial-gradient(w h at x% y%)` → center Alignment(2x−1, 2y−1); the
  // CSS ellipse radii are approximated with a circle (soft glows — visually
  // equivalent). Transparent ends reuse the glow's RGB at alpha 0 so the fade
  // never dips through gray.

  /// Aurora glow 1 — violet `at 72% 16%`, transparent 56%.
  static const auroraVioletGlow = RadialGradient(
    center: Alignment(0.44, -0.68),
    radius: 1.0,
    colors: [WtmColors.auroraViolet, Color(0x00BE78FF)],
    stops: [0.0, 0.56],
  );

  /// Aurora glow 2 — pink `at 16% 86%`, transparent 55%.
  static const auroraPinkGlow = RadialGradient(
    center: Alignment(-0.68, 0.72),
    radius: 0.85,
    colors: [WtmColors.auroraPink, Color(0x00F396CD)],
    stops: [0.0, 0.55],
  );

  /// Aurora glow 3 — plum `at 50% 52%`, transparent 72%.
  static const auroraPlumGlow = RadialGradient(
    center: Alignment(0.0, 0.04),
    radius: 0.72,
    colors: [WtmColors.auroraPlum, Color(0x00603EA8)],
    stops: [0.0, 0.72],
  );

  /// Blush variant base — `linear(162°, #1B1230 → #0A0614)`.
  static const auroraBaseBlush = LinearGradient(
    begin: Alignment(-0.309, -0.951),
    end: Alignment(0.309, 0.951),
    colors: [WtmColors.auroraBaseTop2, WtmColors.auroraBaseBottom],
  );

  /// Blush glow 1 — pink `at 30% 20%`, transparent 55%.
  static const auroraBlushPinkGlow = RadialGradient(
    center: Alignment(-0.4, -0.6),
    radius: 0.95,
    colors: [WtmColors.auroraPinkStrong, Color(0x00F396CD)],
    stops: [0.0, 0.55],
  );

  /// Blush glow 2 — violet `at 75% 85%`, transparent 60%.
  static const auroraBlushVioletGlow = RadialGradient(
    center: Alignment(0.5, 0.7),
    radius: 0.8,
    colors: [WtmColors.auroraVioletStrong, Color(0x008C5FDC)],
    stops: [0.0, 0.6],
  );

  /// Imagery vignette (board `.vig`) — `radial(120% 100% at 50% 40%,
  /// transparent 55%, rgba(5,3,10,.55) 100%)`.
  static const vignetteRadial = RadialGradient(
    center: Alignment(0.0, -0.2),
    radius: 1.1,
    colors: [Color(0x0005030A), WtmColors.vignette],
    stops: [0.55, 1.0],
  );

  /// Scaffold top glow (board phone frame `::before`) — `radial(75% 34% at
  /// 50% −8%, rgba(140,95,220,.18), transparent 70%)`.
  static const scaffoldGlowRadial = RadialGradient(
    center: Alignment(0.0, -1.16),
    radius: 0.85,
    colors: [WtmColors.scaffoldGlow, Color(0x008C5FDC)],
    stops: [0.0, 0.7],
  );

  /// The Orb core sphere — `radial(circle at 34% 28%, #F2E4FF 0%, #C89BFF 32%,
  /// #8A63E8 58%, #3D2578 82%, #1E1240 100%)`.
  static const orbCore = RadialGradient(
    center: Alignment(-0.32, -0.44),
    radius: 0.98,
    colors: [
      WtmColors.orbCore1,
      WtmColors.orbCore2,
      WtmColors.orbCore3,
      WtmColors.orbCore4,
      WtmColors.orbCore5,
    ],
    stops: [0.0, 0.32, 0.58, 0.82, 1.0],
  );

  /// Fabric-tile inner shade (board `.tile::before`) — `radial(120% 90% at
  /// 20% 100%, rgba(0,0,0,.38), transparent 55%)`.
  static const swatchShadeRadial = RadialGradient(
    center: Alignment(-0.6, 1.0),
    radius: 1.05,
    colors: [WtmColors.swatchShade, Color(0x00000000)],
    stops: [0.0, 0.55],
  );
}

/// Fabric-swatch placeholder colorways c1–c8 (§1.3) — image loading
/// placeholders + empty tiles. All run at the board's `linear(152°)`.
abstract final class WtmSwatch {
  static const _begin = Alignment(-0.469, -0.883);
  static const _end = Alignment(0.469, 0.883);

  static const c1 = LinearGradient(
    begin: _begin, end: _end,
    colors: [Color(0xFF332C3E), Color(0xFF15101C)], // noir
  );
  static const c2 = LinearGradient(
    begin: _begin, end: _end,
    colors: [Color(0xFFEBDFCB), Color(0xFFC4B092)], // ivory
  );
  static const c3 = LinearGradient(
    begin: _begin, end: _end,
    colors: [Color(0xFF714C93), Color(0xFF3A2458)], // plum
  );
  static const c4 = LinearGradient(
    begin: _begin, end: _end,
    colors: [Color(0xFFC46BC0), Color(0xFF7C3A8E)], // orchid
  );
  static const c5 = LinearGradient(
    begin: _begin, end: _end,
    colors: [Color(0xFF8D6D40), Color(0xFF4C3A1E)], // bronze
  );
  static const c6 = LinearGradient(
    begin: _begin, end: _end,
    colors: [Color(0xFF823452), Color(0xFF48192F)], // wine
  );
  static const c7 = LinearGradient(
    begin: _begin, end: _end,
    colors: [Color(0xFF4C5069), Color(0xFF22253A)], // slate
  );
  static const c8 = LinearGradient(
    begin: _begin, end: _end,
    colors: [Color(0xFFDBACBB), Color(0xFF9A6377)], // blush
  );

  static const all = [c1, c2, c3, c4, c5, c6, c7, c8];

  /// Rotating colorway — grids pass their item index.
  static LinearGradient at(int index) => all[index % all.length];
}

/// WTM shadow recipes extracted from the board CSS.
abstract final class WtmShadows {
  /// Gradient CTA — `0 10px 30px -10px rgba(160,110,255,.55)`.
  static const cta = [
    BoxShadow(
      color: WtmColors.ctaGlow,
      blurRadius: 30,
      offset: Offset(0, 10),
      spreadRadius: -10,
    ),
  ];

  /// Selected-tile badge — `0 3px 10px rgba(140,90,255,.5)`.
  static const selBadge = [
    BoxShadow(
      color: WtmColors.selBadgeShadow,
      blurRadius: 10,
      offset: Offset(0, 3),
    ),
  ];
}
