import 'package:flutter/material.dart';

import '../../theme/wtm_typography.dart';

/// Section marker (board `.eyebrow`) — 9px Outfit 500, `.30em` tracking,
/// UPPERCASE, goldDim. Pass [color] for the board's rare recolors (e.g. the
/// orchid Atelier-assistant eyebrow).
class EyebrowLabel extends StatelessWidget {
  const EyebrowLabel(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: color == null
          ? WtmType.eyebrow
          : WtmType.eyebrow.copyWith(color: color),
    );
  }
}
