import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/platform_capabilities.dart';

/// WHY the app is asking for an image.
///
/// Every image request in the app names its purpose, because the answer to
/// "where may this picture come from?" is not a property of the platform and
/// never was — it is a property of what the picture IS. A photograph of a
/// jacket lying on a bed and a photograph of the user's body are both "an
/// image the user chose", and treating them the same is exactly how the
/// person-image rule leaks.
///
/// Adding a value here does not grant anything. [MediaSourcePolicy.forPurpose]
/// decides, and an unnamed purpose keeps today's behaviour.
enum ImagePurpose {
  /// The person a garment is rendered ONTO — MoodMirror's body photo, the
  /// try-on gallery, the legacy avatar flow. On iOS/iPadOS this must be a
  /// fresh capture from the app's own live camera; nothing from the device
  /// Photo Library, Files, the clipboard, a URL or a share sheet may become
  /// one.
  tryOnPersonImage,

  /// A garment being added to (or re-shot for) the digital closet. Photo
  /// Library selection is the primary path on every platform and is unchanged
  /// — this is what `NSPhotoLibraryUsageDescription` exists for.
  closetGarmentImage,

  /// A community post / compose attachment.
  communityImage,

  /// A profile or avatar display picture (NOT the try-on body).
  profileImage,

  /// A giveaway listing photograph.
  giveawayImage,
}

/// Where an image of a given [ImagePurpose] is allowed to come from.
enum MediaSourceRule {
  /// The platform's existing choices — Camera and Photo Library — unchanged.
  deviceCameraAndLibrary,

  /// A fresh capture from the app's OWN live camera session, and nothing
  /// else. No gallery, no Files, no clipboard, no URL import, no share-sheet
  /// import, and no system `image_picker` camera sheet either.
  ///
  /// It says nothing about WHICH lens. The screen defaults to the front lens
  /// for solo capture and lets the user switch to the rear one when somebody
  /// is helping them — both are the same in-app session, and that is the
  /// property this rule is actually about. Naming it `liveFrontCameraOnly`
  /// made the lens sound like the restriction, which would have made adding
  /// the rear lens look like a weakening of the gate when it changes nothing
  /// about where a person image may come from.
  liveCameraOnly,
}

/// The ONE place that answers "may this purpose use the Photo Library here?".
///
/// This is deliberately NOT a boolean like `galleryDisabledOnIos`. A global
/// switch would have to be re-checked (and re-reasoned about) at every call
/// site, and the first surface that forgot would either lose Closet's gallery
/// upload or quietly re-open the person-image hole. Asking a purpose-aware
/// policy makes the correct answer the easy one, and makes the wrong answer
/// impossible to express.
///
/// Injected through [mediaSourcePolicyProvider] rather than read from the host,
/// so an Android regression and an iPad regression are both provable from one
/// Windows dev box — the same reasoning that put [PlatformCapabilities] behind
/// a provider.
@immutable
class MediaSourcePolicy {
  const MediaSourcePolicy(this.platform);

  final PlatformCapabilities platform;

  /// True on iOS and iPadOS native builds. iPadOS reports
  /// [TargetPlatform.iOS], which is what the App Review environment runs.
  ///
  /// A web build is excluded for the same reason Guest Mode excludes it:
  /// Safari on iPadOS reports iOS, has no `camera` plugin, and is not the
  /// binary under review.
  bool get _isAppleMobile =>
      !platform.isWeb && platform.platform == TargetPlatform.iOS;

  /// The rule for [purpose] on this platform.
  ///
  /// Exactly one cell of this matrix is new: iOS + [ImagePurpose.tryOnPersonImage].
  /// Every other combination answers [MediaSourceRule.deviceCameraAndLibrary],
  /// which is what the app does today — so Android, Closet on both platforms,
  /// profile, community and giveaways cannot be changed by this file.
  MediaSourceRule forPurpose(ImagePurpose purpose) {
    if (_isAppleMobile && purpose == ImagePurpose.tryOnPersonImage) {
      return MediaSourceRule.liveCameraOnly;
    }
    return MediaSourceRule.deviceCameraAndLibrary;
  }

  /// Whether the device Photo Library may be offered for [purpose].
  ///
  /// The question a source-picker actually asks. Note what it does NOT do:
  /// it never answers "no" for [ImagePurpose.closetGarmentImage], on any
  /// platform, because Closet's gallery upload is a shipped, required path.
  bool allowsPhotoLibrary(ImagePurpose purpose) =>
      forPurpose(purpose) != MediaSourceRule.liveCameraOnly;

  /// Whether [purpose] must go through the app's own in-app live camera.
  bool requiresLiveCamera(ImagePurpose purpose) =>
      forPurpose(purpose) == MediaSourceRule.liveCameraOnly;

  @override
  bool operator ==(Object other) =>
      other is MediaSourcePolicy && other.platform == platform;

  @override
  int get hashCode => platform.hashCode;

  @override
  String toString() => 'MediaSourcePolicy(${platform.platform.name})';
}

/// Thrown when a caller asks for an image from a source the policy forbids for
/// that purpose — in practice, a Photo Library / Files / URL person image on
/// iOS, or the system camera sheet, which is also not this app's live session.
///
/// It is a TYPED failure rather than a silent null because the two mean
/// opposite things to the screen above: a null is "the user changed their
/// mind" and must leave the flow exactly as it was, while this is "that route
/// does not exist here" and deserves an explanation. Callers that do not know
/// about it will not swallow it either — an unhandled throw is loud, and loud
/// is the correct failure direction for a gate.
///
/// It is raised BEFORE any permission prompt, picker, file copy, upload,
/// network call, AI job or credit operation.
@immutable
class UnsupportedImageSourceException implements Exception {
  const UnsupportedImageSourceException({
    required this.purpose,
    required this.rule,
  });

  final ImagePurpose purpose;
  final MediaSourceRule rule;

  /// A stable, non-PII code for diagnostics and analytics.
  String get code => 'UNSUPPORTED_IMAGE_SOURCE';

  @override
  String toString() =>
      'UnsupportedImageSourceException(${purpose.name} requires ${rule.name})';
}

/// The app-wide media-source policy. Override in tests:
/// `mediaSourcePolicyProvider.overrideWithValue(
///    const MediaSourcePolicy(PlatformCapabilities(platform: TargetPlatform.android)))`.
///
/// Derived from [platformCapabilitiesProvider] (not a second source of truth),
/// so a test that pins the platform moves this too.
final mediaSourcePolicyProvider = Provider<MediaSourcePolicy>(
  (ref) => MediaSourcePolicy(ref.watch(platformCapabilitiesProvider)),
);
