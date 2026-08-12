import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../closet/wtm_add_garment_screen.dart' show WtmGoldProgress;

/// Floating snack styled for the noir shell, raised above the bottom nav.
///
/// [dismissOnPop] ties the message to the route that raised it.
/// `ScaffoldMessenger` is a single app-level widget, so a snack shown from a
/// pushed screen normally outlives that screen — which is right for "saved",
/// "deleted" and "this giveaway is gone", all of which are explanations for
/// leaving and have to survive the leaving. It is wrong for a TRANSIENT error
/// about something on the screen itself: a refused link inside the article
/// reader was still on screen after the user had backed out and opened a
/// product, where it reads as a complaint about the product.
///
/// So it is opt-in, and the opting is done by whoever knows which kind of
/// message it is. Off by default keeps every existing confirmation behaving
/// exactly as it did.
///
/// It has no effect from a shell TAB, where `ModalRoute` is the shell itself
/// and is never popped.
void wtmSnack(
  BuildContext context,
  String message, {
  bool dismissOnPop = false,
}) {
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  final controller = messenger.showSnackBar(
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

  if (!dismissOnPop) return;
  final route = ModalRoute.of(context);
  if (route == null) return;
  var closed = false;
  controller.closed.then((_) => closed = true);
  // `hideCurrentSnackBar`, not `controller.close()`: closing a controller that
  // is no longer the live one trips an assertion inside ScaffoldMessenger, and
  // by the time a route pops another screen may well have shown its own.
  route.popped.whenComplete(() {
    if (!closed && messenger.mounted) messenger.hideCurrentSnackBar();
  });
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
