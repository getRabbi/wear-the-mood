import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/media/media_source_policy.dart';
import 'package:app/core/platform/platform_capabilities.dart';

/// THE MATRIX.
///
/// One cell of it is new — iOS + a Try-On person image — and the whole point of
/// these tests is that the other nineteen are provably not. Because the policy
/// is injected rather than read from the host, an iPad Air answer and an
/// Android answer are both provable from a Windows dev box.
void main() {
  MediaSourcePolicy on(TargetPlatform platform, {bool web = false}) =>
      MediaSourcePolicy(
        PlatformCapabilities(platform: platform, isWeb: web),
      );

  group('iOS / iPadOS', () {
    final ios = on(TargetPlatform.iOS);

    test('a Try-On person image is live front camera only', () {
      expect(
        ios.forPurpose(ImagePurpose.tryOnPersonImage),
        MediaSourceRule.liveFrontCameraOnly,
      );
      expect(ios.requiresLiveFrontCamera(ImagePurpose.tryOnPersonImage), isTrue);
    });

    test('a Try-On person image may NOT use the photo library', () {
      expect(ios.allowsPhotoLibrary(ImagePurpose.tryOnPersonImage), isFalse);
    });

    test('a CLOSET garment keeps camera AND photo library', () {
      // The single most important negative in this file. Closet's gallery
      // upload is shipped, is what NSPhotoLibraryUsageDescription exists for,
      // and must not be collateral damage of the person-image rule.
      expect(
        ios.forPurpose(ImagePurpose.closetGarmentImage),
        MediaSourceRule.deviceCameraAndLibrary,
      );
      expect(ios.allowsPhotoLibrary(ImagePurpose.closetGarmentImage), isTrue);
    });

    test('profile, community and giveaway images are untouched', () {
      for (final purpose in const [
        ImagePurpose.profileImage,
        ImagePurpose.communityImage,
        ImagePurpose.giveawayImage,
      ]) {
        expect(
          ios.allowsPhotoLibrary(purpose),
          isTrue,
          reason: '${purpose.name} must keep its existing sources',
        );
      }
    });

    test('exactly ONE purpose is restricted', () {
      final restricted = ImagePurpose.values
          .where(ios.requiresLiveFrontCamera)
          .toList();
      expect(restricted, [ImagePurpose.tryOnPersonImage]);
    });
  });

  group('Android', () {
    final android = on(TargetPlatform.android);

    test('every purpose keeps camera and photo library', () {
      for (final purpose in ImagePurpose.values) {
        expect(
          android.forPurpose(purpose),
          MediaSourceRule.deviceCameraAndLibrary,
          reason: 'Android ${purpose.name} must not move',
        );
        expect(android.allowsPhotoLibrary(purpose), isTrue);
      }
    });

    test('a Try-On person image is NOT forced through a camera', () {
      expect(
        android.requiresLiveFrontCamera(ImagePurpose.tryOnPersonImage),
        isFalse,
      );
    });
  });

  group('no other platform inherits the iOS policy', () {
    test('macOS, Windows, Linux and Fuchsia keep their sources', () {
      for (final platform in TargetPlatform.values) {
        if (platform == TargetPlatform.iOS) continue;
        final policy = on(platform);
        for (final purpose in ImagePurpose.values) {
          expect(
            policy.requiresLiveFrontCamera(purpose),
            isFalse,
            reason: '${platform.name}/${purpose.name} must be unchanged',
          );
        }
      }
    });

    test('web on an iOS user agent is not the native app', () {
      // Safari on iPadOS reports TargetPlatform.iOS and has no camera plugin.
      // Restricting it would break a surface, not protect one.
      final web = on(TargetPlatform.iOS, web: true);
      expect(web.requiresLiveFrontCamera(ImagePurpose.tryOnPersonImage), isFalse);
      expect(web.allowsPhotoLibrary(ImagePurpose.tryOnPersonImage), isTrue);
    });
  });

  group('the provider is derived, not a second source of truth', () {
    test('pinning the platform moves the media policy with it', () {
      final container = ProviderContainer(
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(
            const PlatformCapabilities(platform: TargetPlatform.iOS),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container
            .read(mediaSourcePolicyProvider)
            .requiresLiveFrontCamera(ImagePurpose.tryOnPersonImage),
        isTrue,
      );
    });

    test('an Android-pinned container answers Android', () {
      final container = ProviderContainer(
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(
            const PlatformCapabilities(platform: TargetPlatform.android),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container
            .read(mediaSourcePolicyProvider)
            .requiresLiveFrontCamera(ImagePurpose.tryOnPersonImage),
        isFalse,
      );
    });
  });

  group('the refusal is typed and carries why', () {
    test('an unsupported source names the purpose and the rule', () {
      const e = UnsupportedImageSourceException(
        purpose: ImagePurpose.tryOnPersonImage,
        rule: MediaSourceRule.liveFrontCameraOnly,
      );
      expect(e.code, 'UNSUPPORTED_IMAGE_SOURCE');
      expect(e.toString(), contains('tryOnPersonImage'));
      expect(e.toString(), contains('liveFrontCameraOnly'));
    });
  });

  group('the iOS result-screen rules travel with the same platform authority', () {
    test('iOS requires the label, the watermark and Report; denies Adjust', () {
      const ios = PlatformCapabilities(platform: TargetPlatform.iOS);
      expect(ios.requiresAiGeneratedLabel, isTrue);
      expect(ios.requiresWatermarkedShare, isTrue);
      expect(ios.showsResultReport, isTrue);
      expect(ios.allowsResultAdjust, isFalse);
    });

    test('Android keeps Adjust and gains nothing', () {
      const android = PlatformCapabilities(platform: TargetPlatform.android);
      expect(android.allowsResultAdjust, isTrue);
      expect(android.requiresAiGeneratedLabel, isFalse);
      expect(android.requiresWatermarkedShare, isFalse);
      expect(android.showsResultReport, isFalse);
    });

    test('no other platform picks up the iOS result rules', () {
      for (final platform in TargetPlatform.values) {
        if (platform == TargetPlatform.iOS) continue;
        final p = PlatformCapabilities(platform: platform);
        expect(p.requiresAiGeneratedLabel, isFalse, reason: platform.name);
        expect(p.requiresWatermarkedShare, isFalse, reason: platform.name);
        expect(p.showsResultReport, isFalse, reason: platform.name);
        expect(p.allowsResultAdjust, isTrue, reason: platform.name);
      }
    });
  });
}
