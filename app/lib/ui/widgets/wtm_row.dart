import 'package:flutter/material.dart';

import '../../shared/widgets/pressable_scale.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_typography.dart';
import 'wtm_icons.dart';

/// List row (board `.row` — settings screen + Upload Hub): gold-framed 34px
/// icon well, title + optional micro subtitle, chevron. §4's `SettingsRow`.
class WtmRow extends StatelessWidget {
  const WtmRow({
    super.key,
    required this.glyph,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.titleColor,
    this.iconColor,
  });

  final WtmGlyph glyph;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Replaces the default chevron (e.g. a [GoldPill] or value micro).
  final Widget? trailing;

  /// Overrides for danger rows (Delete Account).
  final Color? titleColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12), // .row
      decoration: BoxDecoration(
        gradient: WtmGradients.rowFill,
        borderRadius: BorderRadius.circular(15), // .row radius
        border: Border.all(color: WtmColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 34, // .ricon
            height: 34,
            decoration: BoxDecoration(
              color: WtmColors.riconBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: WtmColors.riconBorder),
            ),
            alignment: Alignment.center,
            child: WtmIcon(
              glyph,
              size: 15,
              color: iconColor ?? WtmColors.gold,
            ),
          ),
          const SizedBox(width: 12), // .row gap
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleColor == null
                      ? WtmType.label
                      : WtmType.label.copyWith(color: titleColor),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WtmType.micro,
                  ),
                ],
              ],
            ),
          ),
          trailing ??
              const WtmIcon(WtmGlyph.chevron, size: 15, color: WtmColors.faint),
        ],
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: subtitle == null ? title : '$title. $subtitle',
      child: ExcludeSemantics(
        child: PressableScale(
          scale: 0.98,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: row,
          ),
        ),
      ),
    );
  }
}
