import 'package:flutter/material.dart';

import 'wtm_colors.dart';

/// Wear The Mood — the shared "smoked glass" surface layer.
///
/// The board (see [WtmColors]) describes what a control is made of; this file
/// describes how one reads at rest, under a finger, when it is on, and when it
/// is off. Those four faces used to be improvised per screen — a hairline at
/// white @2% over a `#08060F` page is a control you can only find by
/// remembering where it was — so they live here once and every icon button,
/// chip, nav item and overlay action pulls from the same set.
///
/// Two rules the values obey:
///
/// * **Dark glass, not white glass.** Every fill is white at a single-digit
///   percentage over the noir page, so the surface separates from the
///   background without ever reading grey.
/// * **Contrast comes from the rim, not the fill.** On a near-black page a
///   drop shadow is close to invisible, so depth is carried by the hairline
///   border. That is also why raising a fill by 4% is enough here and would be
///   garish on a light theme.
abstract final class WtmGlass {
  // ---- Icon buttons / small controls (resting) ----

  /// Resting fill for a glass icon button — white @ 9%.
  static const fill = Color(0x17FFFFFF);

  /// Resting border — white @ 17%. The rim is what makes the control findable
  /// on black; it is deliberately brighter than [WtmColors.line] (a divider).
  static const border = Color(0x2BFFFFFF);

  /// Under the finger: the fill brightens rather than dims, so the press reads
  /// as the surface catching light. White @ 20%.
  static const fillPressed = Color(0x33FFFFFF);

  /// Pressed rim — white @ 34%.
  static const borderPressed = Color(0x57FFFFFF);

  /// Glyph on a resting glass surface — near-full-strength text, not the 56%
  /// secondary-text tint an icon used to inherit.
  static const foreground = Color(0xF2EFEAF6);

  /// Disabled: still legible (a control you can read but not press), never the
  /// 20%-opacity ghost that leaves users guessing what it was.
  static const fillDisabled = Color(0x0AFFFFFF);
  static const borderDisabled = Color(0x14FFFFFF);
  static const foregroundDisabled = Color(0x73EFEAF6);

  // ---- Selected / active ----

  /// Gold wash behind an active control (gold @ 16%).
  static const selectedFill = Color(0x29D9BE95);

  /// Active rim — gold @ 62%.
  static const selectedBorder = Color(0x9ED9BE95);

  /// Active glyph — the app's existing accent, never a new colour.
  static const selectedForeground = WtmColors.gold;

  /// Halo under an active control. A shadow, so it costs no layout.
  static const selectedGlow = <BoxShadow>[
    BoxShadow(color: Color(0x3DD9BE95), blurRadius: 14, spreadRadius: -2),
  ];

  // ---- Buttons on top of imagery ----
  //
  // A photo can be black, blush, or blown-out white, so an overlay control
  // cannot borrow contrast from the page. These carry their own: a mostly
  // opaque noir puck plus a bright rim, which stays readable on every one of
  // those backgrounds.

  /// Overlay puck fill — noir @ 72%.
  static const overlayFill = Color(0xB80A0712);

  /// Overlay rim — white @ 30%.
  static const overlayBorder = Color(0x4DFFFFFF);

  /// Overlay pressed fill — noir @ 88%.
  static const overlayFillPressed = Color(0xE00A0712);

  /// Overlay pressed rim — white @ 48%.
  static const overlayBorderPressed = Color(0x7AFFFFFF);

  /// Overlay glyph — pure white; anything softer sinks into a bright photo.
  static const overlayForeground = Color(0xFFFFFFFF);

  /// A tight contact shadow so the puck separates from a light image.
  static const overlayShadow = <BoxShadow>[
    BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 2)),
  ];

  // ---- Bottom navigation ----

  /// Inactive nav glyph/label. The board's [WtmColors.faint] (34%) is a
  /// micro-copy tint; on a nav destination it read as disabled.
  ///
  /// Solid, like the text tokens: an 8px tracked label is the worst possible
  /// candidate for translucency, and here it would be compositing over a
  /// BLURRED backdrop whose colour changes with whatever scrolled underneath.
  static const navInactive = Color(0xFFADA5BC); // 7.8:1 over bright content

  /// Blur behind the nav wash. ONE backdrop filter for the whole app — see
  /// [WtmBlur].
  static const navBlurSigma = 18.0;
}

/// Elevation recipes.
///
/// There is deliberately only one, and it is not a card shadow. A drop shadow
/// lifts a surface by darkening what is behind it, and on a `#08060F` page
/// there is nothing left to darken — a shadow under a resting card is pure
/// overdraw for no pixels of effect, repeated once per card per frame down a
/// scrolling feed. Cards separate from the page by fill and border instead
/// (see [WtmGradients.cardFill], which also records why a rim light is not an
/// option through that gradient).
///
/// Shadows earn their place only where the thing behind them is NOT the page:
/// content scrolling under the nav, and photography under an overlay control.
abstract final class WtmElevation {
  /// Chrome that content passes beneath — the bottom nav. Cast UPWARD, since
  /// what needs separating is above the bar, not below it.
  static const chrome = <BoxShadow>[
    BoxShadow(color: Color(0x5C000000), blurRadius: 22, offset: Offset(0, -8)),
  ];
}

/// Blur budget (CLAUDE.md §4 / task §8 — performance safety).
///
/// Real backdrop blur is reserved for surfaces that are **static and few**: the
/// bottom nav, sheet headers, a full-screen overlay bar. Anything that repeats
/// inside a scrolling list uses the translucent-fill + rim + shadow treatment
/// instead, because a `BackdropFilter` per card re-samples the layer below on
/// every frame and is the fastest way to lose 60fps on a mid-range Android.
abstract final class WtmBlur {
  /// Sigma for chrome that sits over scrolling content (bottom nav).
  static const chrome = 18.0;

  /// Whether blur is worth painting at all.
  ///
  /// Flutter exposes no reduce-transparency flag, so reduce-motion stands in
  /// for it: a user who has asked the OS to calm things down gets the solid
  /// wash instead. Same layout either way — the gradient underneath is opaque
  /// enough to carry the bar on its own, which is also what keeps this a
  /// progressive enhancement rather than something the design depends on.
  static bool enabled(BuildContext context) =>
      !MediaQuery.of(context).disableAnimations;
}

/// The standard card surface: the board's fill (which now carries its own rim
/// light) plus the hairline rim.
///
/// Screens across the app compose this same [BoxDecoration] inline, which is
/// fine and stays fine — the values behind it are shared, so they cannot drift
/// even where the recipe is written out longhand. This exists so anything NEW
/// has one obvious thing to call.
BoxDecoration wtmCardDecoration({double radius = 18.0, Color? borderColor}) =>
    BoxDecoration(
      gradient: WtmGradients.cardFill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? WtmColors.line),
    );
