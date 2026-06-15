import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Standard page chrome (CLAUDE.md §4) — a Scaffold with a clean app bar and a
/// safe, consistently-padded body. Keeps secondary/full-screen routes visually
/// uniform without each screen re-deriving padding + safe areas.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.floatingActionButton,
    this.padHorizontal = true,
    this.safeArea = true,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final Widget? floatingActionButton;
  final bool padHorizontal;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    Widget content = body;
    if (padHorizontal) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        child: content,
      );
    }
    if (safeArea) content = SafeArea(child: content);

    return Scaffold(
      appBar: title == null && bottom == null && actions == null
          ? null
          : AppBar(
              title: title == null ? null : Text(title!),
              actions: actions,
              leading: leading,
              bottom: bottom,
            ),
      floatingActionButton: floatingActionButton,
      body: content,
    );
  }
}
