import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/widgets/widgets.dart';

/// image_picker's OS permission-denial codes (iOS camera/photos, and Android
/// when a permission is declared). A cancelled picker returns null instead of
/// throwing, so any of these means access is switched off (or restricted by
/// parental controls) for the app — not that the user changed their mind.
bool isImagePermissionDenied(Object error) =>
    error is PlatformException &&
    const {
      'camera_access_denied',
      'photo_access_denied',
      'camera_access_restricted',
      'photo_access_restricted',
    }.contains(error.code);

/// Explains a denied camera/photo permission instead of dead-ending (App Store
/// review checks this). On iOS it offers to open the app's own Settings page
/// (`app-settings:` == UIApplication.openSettingsURLString); elsewhere it shows
/// the explanation as a snack — Android's picker/camera flows are permissionless
/// for this app, so denial there is not reachable in practice.
Future<void> showImagePermissionHelp(
  BuildContext context, {
  required bool camera,
}) async {
  final l10n = AppLocalizations.of(context);
  final message = camera ? l10n.imagePermCameraOff : l10n.imagePermPhotosOff;
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    wtmSnack(context, message);
    return;
  }
  final open = await wtmConfirmDialog(
    context,
    title: l10n.imagePermTitle,
    message: message,
    confirmLabel: l10n.imagePermOpenSettings,
  );
  if (open) {
    await launchUrl(Uri.parse('app-settings:'));
  }
}
