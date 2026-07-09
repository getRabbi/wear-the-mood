import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../closet/wtm_add_garment_screen.dart' show WtmGoldProgress;

/// Floating snack styled for the noir shell, raised above the bottom nav.
void wtmSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: WtmColors.panel,
        margin: const EdgeInsets.fromLTRB(
          WtmSpace.screenH,
          0,
          WtmSpace.screenH,
          104,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WtmRadius.button),
          side: const BorderSide(color: WtmColors.line),
        ),
        content: Text(message, style: WtmType.body),
      ),
    );
}

/// Generic WTM panel sheet — serif title, optional subtitle, then content.
/// Sizes to content and scrolls on short screens.
Future<void> showWtmSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<Widget> children = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: WtmColors.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(WtmRadius.sheetTop),
      ),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          WtmSpace.screenH,
          WtmSpace.s16,
          WtmSpace.screenH,
          WtmSpace.s18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: WtmType.h1.copyWith(fontSize: 20),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: WtmSpace.s6),
              Text(subtitle, textAlign: TextAlign.center, style: WtmType.sub),
            ],
            if (children.isNotEmpty) ...[
              const SizedBox(height: WtmSpace.s14),
              ...children,
            ],
          ],
        ),
      ),
    ),
  );
}

/// Runs [work] behind a small non-dismissible WTM progress dialog ([label] +
/// the gold progress line), so a multi-second action (upload, save) is never a
/// silent screen (mobile QA: every long action shows visible progress). The
/// dialog closes when the work settles; errors rethrow to the caller.
Future<T> runWithWtmProgress<T>(
  BuildContext context,
  String label,
  Future<T> Function() work,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var closed = false;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xB3050308),
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: WtmColors.panel,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 44,
            vertical: 48,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WtmRadius.card),
            side: const BorderSide(color: WtmColors.line),
          ),
          child: Padding(
            padding: const EdgeInsets.all(WtmSpace.s18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: WtmType.labelMedium,
                ),
                const SizedBox(height: WtmSpace.s14),
                const WtmGoldProgress(),
              ],
            ),
          ),
        ),
      ),
    ).then((_) => closed = true),
  );
  try {
    return await work();
  } finally {
    if (!closed && navigator.mounted) navigator.pop();
  }
}

/// WTM-styled confirm dialog. Resolves true on confirm.
Future<bool> wtmConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: WtmColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WtmRadius.card),
        side: const BorderSide(color: WtmColors.line),
      ),
      title: Text(title, style: WtmType.h2.copyWith(fontSize: 19)),
      content: Text(message, style: WtmType.sub),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: WtmType.label.copyWith(color: WtmColors.muted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            confirmLabel,
            style: WtmType.label.copyWith(
              color: danger ? WtmColors.danger : WtmColors.gold,
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
