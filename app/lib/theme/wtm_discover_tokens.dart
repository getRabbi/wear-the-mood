import 'package:flutter/material.dart';

import 'wtm_typography.dart';

/// Discover design tokens, extracted 1:1 from the approved prototype
/// `wearthemood_discover_prototype_v1.html`.
///
/// The prototype runs the same dark-plum/gold/violet language as the Atelier
/// board, but at its OWN editorial scale — larger serif headings, softer
/// corners, 20px gutters. Those numbers live here rather than in
/// `WtmColors`/`WtmRadius`, so the board's tokens keep meaning what they always
/// meant and nothing in Discover is a magic number.
///
/// CSS provenance is in the comments; alpha percentages are converted to 0–255.
/// Typeface is the app's own serif (Cormorant Garamond) at the prototype's
/// sizes — the prototype writes `Georgia` only because a browser mock cannot
/// load the bundled family.
abstract final class DiscoverTokens {
  // ---- Layout ----

  /// `--pad: 20px` — Discover's horizontal gutter.
  static const pad = 20.0;

  /// `.section { margin-top: 18px }`
  static const sectionGap = 18.0;

  /// `.section-head { margin-bottom: 12px }`
  static const headGap = 12.0;

  // ---- Radii ----
  static const radiusXl = 26.0; // --radius-xl
  static const radiusLg = 22.0; // --radius-lg
  static const radiusMd = 18.0; // --radius-md
  static const radiusStory = 24.0; // .story
  static const radiusEditorial = 24.0; // .editorial
  static const radiusPulse = 20.0; // .daily-pulse
  static const radiusLookItem = 16.0; // .look-item
  static const radiusCta = 17.0; // .primary-btn
  static const radiusIconBtn = 15.0; // .icon-btn
  static const pill = 999.0;

  // ---- Palette ----
  static const text = Color(0xFFF5F0FF); // --text
  static const muted = Color(0xFFA59CB7); // --muted
  static const gold = Color(0xFFD6B68A); // --gold
  static const mint = Color(0xFFA7E9D1); // --mint

  /// `--line: rgba(230,220,255,.11)`
  static const line = Color(0x1CE6DCFF);

  /// `--surface: rgba(255,255,255,.045)`
  static const surface = Color(0x0BFFFFFF);

  /// `.story { border: 1px solid rgba(255,255,255,.14) }`
  static const storyBorder = Color(0x24FFFFFF);

  /// `.story-label { color: #ead5ae }`
  static const storyLabel = Color(0xFFEAD5AE);

  /// `.story-meta { color: #bcb2c9 }`
  static const storyMeta = Color(0xFFBCB2C9);

  /// `.story-badge` — glass capsule over the artwork.
  static const badgeBg = Color(0xA80A0712); // rgba(10,7,18,.66)
  static const badgeBorder = Color(0x2EFFFFFF); // rgba(255,255,255,.18)

  /// `.text-action { color: #cbb9ed }`
  static const textAction = Color(0xFFCBB9ED);

  /// `.feature-label { color: #f0d3a9 }`
  static const featureLabel = Color(0xFFF0D3A9);

  /// `.feature-meta { color: #c2b7cd }`
  static const featureMeta = Color(0xFFC2B7CD);

  /// `.heart` — glass circle over the product image.
  static const heartBg = Color(0x7A0A0712); // rgba(10,7,18,.48)
  static const heartBorder = Color(0x33FFFFFF); // rgba(255,255,255,.20)
  static const heartSavedBg = Color(0xFFF1E8FF); // .heart.saved
  static const heartSavedIcon = Color(0xFF5B2F86);

  /// `.pill` on a product image.
  static const productPillBg = Color(0x9E0C0814); // rgba(12,8,20,.62)

  /// `.choice` / `.choice.active` in the daily-pulse module.
  static const choiceBg = Color(0x0AFFFFFF); // rgba(255,255,255,.04)
  static const choiceOnBg = Color(0xFFEEE7FF);
  static const choiceOnText = Color(0xFF1A1228);

  /// `.plus` — the small badge between look tiles.
  static const plusBg = Color(0xFFE7DEF8);
  static const plusText = Color(0xFF251637);

  /// `.match-score` — mint capsule.
  static const matchBorder = Color(0x33A7E9D1); // rgba(167,233,209,.2)
  static const matchBg = Color(0x14A7E9D1); // rgba(167,233,209,.08)

  /// `.primary-btn { color: #1b1026 }`
  static const ctaText = Color(0xFF1B1026);

  /// `.look-item` fill — `linear(145deg, #2c2045, #110c1c)`.
  static const lookItemTop = Color(0xFF2C2045);
  static const lookItemBottom = Color(0xFF110C1C);

  /// `.look-item.owned::after` chip behind "IN YOUR CLOSET".
  static const ownedChipBg = Color(0xA607050C); // rgba(7,5,12,.65)

  // ---- Gradients ----

  /// `.story.fresh::before` — `linear(145deg, #8c6dff, #f08fd0, #d2b382)`.
  /// The unseen ring: three stops, never a flat colour.
  static const freshRing = LinearGradient(
    begin: Alignment(-0.574, -0.819),
    end: Alignment(0.574, 0.819),
    colors: [Color(0xFF8C6DFF), Color(0xFFF08FD0), Color(0xFFD2B382)],
  );

  /// `.story::after` — bottom scrim, `to top` with three stops.
  static const storyScrim = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Color(0xFA06040D), Color(0xAD06040D), Color(0x1406040D)],
    stops: [0.03, 0.35, 0.70],
  );

  /// `.daily-pulse` fill — `linear(120deg, rgba(140,105,255,.12),
  /// rgba(236,137,204,.06))`.
  static const pulseFill = LinearGradient(
    begin: Alignment(-0.866, -0.5),
    end: Alignment(0.866, 0.5),
    colors: [Color(0x1F8C69FF), Color(0x0FEC89CC)],
  );

  /// `.primary-btn` — `linear(100deg, #7b5cff, #f19bd7)`.
  static const primaryCta = LinearGradient(
    begin: Alignment(-0.985, -0.174),
    end: Alignment(0.985, 0.174),
    colors: [Color(0xFF7B5CFF), Color(0xFFF19BD7)],
  );

  /// `.look-item` fill — `linear(145deg, #2c2045, #110c1c)`.
  static const lookItemFill = LinearGradient(
    begin: Alignment(-0.574, -0.819),
    end: Alignment(0.574, 0.819),
    colors: [lookItemTop, lookItemBottom],
  );

  /// `.look-module` accent — `radial(300px 150px at 100% 0%,
  /// rgba(138,96,255,.17), transparent 75%)`.
  static const lookAccent = RadialGradient(
    center: Alignment(1.0, -1.0),
    radius: 1.05,
    colors: [Color(0x2B8A60FF), Color(0x008A60FF)],
    stops: [0.0, 0.75],
  );

  /// `.feature-card` base — `linear(135deg, #431f50, #120b1f 74%)`.
  static const featureBase = LinearGradient(
    begin: Alignment(-0.707, -0.707),
    end: Alignment(0.707, 0.707),
    colors: [Color(0xFF431F50), Color(0xFF120B1F)],
    stops: [0.0, 0.74],
  );

  /// `.feature-card` blush — `radial(circle at 76% 18%, rgba(249,172,204,.82),
  /// transparent 17%)`.
  static const featureBlush = RadialGradient(
    center: Alignment(0.52, -0.64),
    radius: 0.62,
    colors: [Color(0xD1F9ACCC), Color(0x00F9ACCC)],
    stops: [0.0, 0.55],
  );

  /// `.feature-card` violet — `radial(circle at 82% 18%, rgba(124,91,221,.62),
  /// transparent 36%)`.
  static const featureViolet = RadialGradient(
    center: Alignment(0.64, -0.64),
    radius: 1.0,
    colors: [Color(0x9E7C5BDD), Color(0x007C5BDD)],
    stops: [0.0, 0.72],
  );

  /// `.feature-card::before` — `linear(to top, rgba(7,4,13,.96),
  /// rgba(7,4,13,.10) 70%)`.
  static const featureScrim = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Color(0xF507040D), Color(0x1A07040D)],
    stops: [0.0, 0.70],
  );

  /// `.editorial-art` — `radial(circle at 50% 30%, #9f84c7, #4b3e6b 45%,
  /// #161022 100%)`.
  static const editorialArt = RadialGradient(
    center: Alignment(0.0, -0.4),
    radius: 0.95,
    colors: [Color(0xFF9F84C7), Color(0xFF4B3E6B), Color(0xFF161022)],
    stops: [0.0, 0.45, 1.0],
  );

  /// `.editorial-art` wash — `linear(135deg, rgba(103,74,191,.18),
  /// transparent)`.
  static const editorialWash = LinearGradient(
    begin: Alignment(-0.707, -0.707),
    end: Alignment(0.707, 0.707),
    colors: [Color(0x2E674ABF), Color(0x00674ABF)],
  );

  // ---- Component sizes ----
  static const storyWidth = 132.0; // .story flex-basis
  static const storyHeight = 194.0; // .story height
  static const storyWidthNarrow = 122.0; // @max-width 350
  static const storyHeightNarrow = 184.0;
  static const storyGap = 12.0; // .stories gap

  static const productWidth = 178.0; // .product-card flex-basis
  static const productWidthNarrow = 160.0; // @max-width 350
  static const productGap = 12.0; // .product-strip gap
  static const productAspect = 4 / 5; // .product-image aspect-ratio

  static const iconBtn = 42.0; // .icon-btn
  static const heart = 36.0; // .heart
  static const plusBadge = 18.0; // .plus

  static const featureMinHeight = 208.0; // .feature-card
  static const featurePadding = 19.0;
  static const editorialMinHeight = 166.0; // .editorial
  static const lookPadding = 17.0; // .look-module

  /// The width below which the prototype's `@media (max-width: 350px)` rules
  /// apply: tighter gutter, smaller cards.
  static const narrowBreakpoint = 350.0;

  static double padFor(double width) => width <= narrowBreakpoint ? 15.0 : pad;

  // ---- Type ----

  /// `h1 { font-size: clamp(34px, 9vw, 42px) }` — the Discover wordmark.
  static double titleSizeFor(double width) => (width * 0.09).clamp(34.0, 42.0);

  static TextStyle title(double width) => TextStyle(
    fontFamily: WtmFonts.serif,
    fontSize: titleSizeFor(width),
    fontWeight: FontWeight.w500,
    height: 0.98,
    letterSpacing: titleSizeFor(width) * -0.03,
    color: text,
  );

  /// `.subtitle` — 13px, muted.
  static const subtitle = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 13,
    height: 1.35,
    color: muted,
  );

  /// `.subtitle strong` — the mood word, gold and semibold.
  static const subtitleStrong = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: gold,
  );

  /// `.section-kicker` — 9px, `.24em`, uppercase, gold, weight 700.
  static const kicker = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 9,
    fontWeight: FontWeight.w700,
    letterSpacing: 9 * 0.24,
    color: gold,
  );

  /// `.section-title` / `.look-title` — serif 25px.
  static const sectionTitle = TextStyle(
    fontFamily: WtmFonts.serif,
    fontSize: 25,
    fontWeight: FontWeight.w500,
    height: 1.0,
    color: text,
  );

  /// `.text-action` — 13px lavender.
  static const textActionStyle = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 13,
    color: textAction,
  );

  /// `.story-label` — 8.5px, `.2em`, uppercase, weight 800.
  static const storyLabelStyle = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 8.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 8.5 * 0.2,
    color: storyLabel,
  );

  /// `.story-title` — serif 18px.
  static const storyTitleStyle = TextStyle(
    fontFamily: WtmFonts.serif,
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.04,
    color: text,
  );

  /// `.story-meta` — 10px.
  static const storyMetaStyle = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 10,
    color: storyMeta,
  );

  /// `.story-badge` — 8px, `.08em`, weight 800, white.
  static const badgeStyle = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 8,
    fontWeight: FontWeight.w800,
    letterSpacing: 8 * 0.08,
    color: Colors.white,
  );

  /// `.brand` — 8px, `.14em`, uppercase, gold, weight 800.
  static const brand = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 8,
    fontWeight: FontWeight.w800,
    letterSpacing: 8 * 0.14,
    color: gold,
  );

  /// `.product-name` — serif 17px.
  static const productName = TextStyle(
    fontFamily: WtmFonts.serif,
    fontSize: 17,
    fontWeight: FontWeight.w500,
    height: 1.05,
    color: text,
  );

  /// `.price` — 13px weight 700.
  static const price = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: text,
  );

  /// `.reason` / `.look-sub` — muted small copy.
  static const reason = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 10,
    color: muted,
  );

  static const lookSub = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 11,
    color: muted,
  );

  /// `.pill` on a product image — 8px, `.08em`, uppercase, weight 800.
  static const productPill = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 8,
    fontWeight: FontWeight.w800,
    letterSpacing: 8 * 0.08,
    color: text,
  );

  /// `.match-score` — 10px mint.
  static const matchScore = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 10,
    color: mint,
  );

  /// `.pulse-copy strong` — 13px.
  static const pulseTitle = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: text,
  );

  /// `.pulse-copy span` — 11px muted.
  static const pulseSub = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 11,
    color: muted,
  );

  /// `.choice` — 10px.
  static const choice = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 10,
    color: text,
  );

  /// `.primary-btn` — weight 800 on the plum text colour.
  static const primaryCtaLabel = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 13,
    fontWeight: FontWeight.w800,
    color: ctaText,
  );

  /// `.feature-label` — 9px, `.22em`, uppercase, weight 800.
  static const featureLabelStyle = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 9,
    fontWeight: FontWeight.w800,
    letterSpacing: 9 * 0.22,
    color: featureLabel,
  );

  /// `.feature-title` — serif 28px.
  static const featureTitle = TextStyle(
    fontFamily: WtmFonts.serif,
    fontSize: 28,
    fontWeight: FontWeight.w500,
    height: 1.02,
    color: text,
  );

  /// `.feature-meta` — 11px.
  static const featureMetaStyle = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 11,
    color: featureMeta,
  );

  /// `.feature-action` — 12px weight 700, white.
  static const featureAction = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  /// `.editorial-copy .feature-label` — the same kicker at 8px.
  static const editorialLabel = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 8,
    fontWeight: FontWeight.w800,
    letterSpacing: 8 * 0.22,
    color: featureLabel,
  );

  /// `.editorial-title` — serif 21px.
  static const editorialTitle = TextStyle(
    fontFamily: WtmFonts.serif,
    fontSize: 21,
    fontWeight: FontWeight.w500,
    height: 1.08,
    color: text,
  );

  /// `.look-item.owned::after` — 6.5px, `.08em`, uppercase.
  static const ownedChip = TextStyle(
    fontFamily: WtmFonts.sans,
    fontSize: 6.5,
    letterSpacing: 6.5 * 0.08,
    color: text,
  );
}
