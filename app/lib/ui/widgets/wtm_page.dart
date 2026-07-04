import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import 'wtm_icon_button.dart';
import 'wtm_icons.dart';
import 'wtm_scaffold.dart';

/// Bottom padding for shell pages so content clears the translucent floating
/// nav (extendBody shell).
const wtmNavClearance = 120.0;

/// Standard pushed-page chrome: the board's `.navhead` (back · serif title +
/// eyebrow · trailing) over a padded ListView. [fullBleed] wraps in a
/// [WtmScaffold] for routes hosted OUTSIDE the shell.
class WtmPage extends StatelessWidget {
  const WtmPage({
    super.key,
    required this.title,
    this.eyebrow,
    this.showBack = true,
    this.trailing,
    this.children = const [],
    this.fullBleed = false,
    this.onBack,
    this.header,
  });

  final String title;

  /// Small uppercase line under the title (board `.navhead i`).
  final String? eyebrow;
  final bool showBack;
  final Widget? trailing;
  final List<Widget> children;
  final bool fullBleed;
  final VoidCallback? onBack;

  /// Optional widgets pinned between the navhead and the scrolling list.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WtmSpace.screenH,
              WtmSpace.s8,
              WtmSpace.screenH,
              WtmSpace.s8,
            ),
            child: Row(
              children: [
                if (showBack)
                  WtmIconButton(
                    WtmGlyph.back,
                    semanticLabel:
                        MaterialLocalizations.of(context).backButtonTooltip,
                    onTap: onBack ?? () => wtmPageBack(context),
                  )
                else
                  const SizedBox(width: 44),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WtmType.h2.copyWith(fontSize: 17),
                      ),
                      if (eyebrow != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          eyebrow!.toUpperCase(),
                          maxLines: 1,
                          style: WtmType.eyebrow.copyWith(
                            letterSpacing: 2.52, // .28em × 9 (.navhead i)
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                trailing ?? const SizedBox(width: 44),
              ],
            ),
          ),
          ?header,
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                WtmSpace.screenH,
                WtmSpace.s10,
                WtmSpace.screenH,
                wtmNavClearance,
              ),
              children: children,
            ),
          ),
        ],
      ),
    );
    return fullBleed ? WtmScaffold(body: body) : body;
  }
}

/// Back that can never dead-end: pop when possible, else land on Home.
void wtmPageBack(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(AppRoute.wtmHome);
  }
}
