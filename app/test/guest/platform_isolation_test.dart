import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/core/auth/guest_capabilities.dart';
import 'package:app/core/auth/guest_session.dart';
import 'package:app/core/platform/platform_capabilities.dart';
import 'package:app/core/router/routes.dart';

/// PLATFORM ISOLATION — the promise that Guest Mode is iOS-only.
///
/// Android's launch and auth experience is already shipped and must not move by
/// a pixel or a route. Because [PlatformCapabilities] is injected rather than
/// read from the host, both platforms are provable from one machine — which is
/// the only way a Windows dev box can prove anything about an iPad.
void main() {
  const ios = PlatformCapabilities(platform: TargetPlatform.iOS);
  const android = PlatformCapabilities(platform: TargetPlatform.android);

  group('platform capability policy', () {
    test('iOS supports Guest Mode', () {
      expect(ios.guestModeSupported, isTrue);
    });

    test('Android does NOT support Guest Mode', () {
      expect(android.guestModeSupported, isFalse);
    });

    test('no other platform supports Guest Mode', () {
      for (final platform in TargetPlatform.values) {
        if (platform == TargetPlatform.iOS) continue;
        expect(
          PlatformCapabilities(platform: platform).guestModeSupported,
          isFalse,
          reason: '${platform.name} must never offer Guest Mode',
        );
      }
    });

    test('web on an iOS user agent is still denied', () {
      // Safari on iPadOS reports TargetPlatform.iOS. A web build is not the
      // native app and has no business entering Guest Mode.
      const webOnIos = PlatformCapabilities(
        platform: TargetPlatform.iOS,
        isWeb: true,
      );
      expect(webOnIos.guestModeSupported, isFalse);
    });
  });

  group('guest state cannot be entered off iOS', () {
    ProviderContainer boot(PlatformCapabilities platform) {
      final container = ProviderContainer(
        overrides: [platformCapabilitiesProvider.overrideWithValue(platform)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('enterGuest is a no-op on Android', () async {
      final container = boot(android);
      await container.read(guestSessionProvider.notifier).enterGuest();

      expect(container.read(guestSessionProvider), isFalse);
      expect(container.read(isGuestSessionProvider), isFalse);
    });

    test('restore never reads a persisted flag on Android', () async {
      final container = boot(android);
      // Even if a flag somehow existed on disk (a restored backup, a shared
      // profile), Android resolves straight to "not a guest" without reading it.
      await container.read(guestSessionProvider.notifier).restore();

      expect(container.read(guestSessionProvider), isFalse);
    });

    test('every non-iOS platform refuses enterGuest', () async {
      for (final platform in TargetPlatform.values) {
        if (platform == TargetPlatform.iOS) continue;
        final container = boot(PlatformCapabilities(platform: platform));
        await container.read(guestSessionProvider.notifier).enterGuest();
        expect(
          container.read(guestSessionProvider),
          isFalse,
          reason: '${platform.name} must not be able to become a guest',
        );
      }
    });
  });

  group('session state precedence', () {
    test('unknown is never treated as authenticated', () {
      expect(AppSessionState.unknown.canPerformProtectedActions, isFalse);
    });

    test('signedOut is never treated as authenticated', () {
      expect(AppSessionState.signedOut.canPerformProtectedActions, isFalse);
    });

    test('guest is never treated as authenticated', () {
      expect(AppSessionState.guest.canPerformProtectedActions, isFalse);
      expect(AppSessionState.guest.isGuest, isTrue);
    });

    test('only authenticated may perform protected actions', () {
      final allowed = AppSessionState.values
          .where((s) => s.canPerformProtectedActions)
          .toList();
      expect(allowed, [AppSessionState.authenticated]);
    });

    test('authenticated is not a guest', () {
      expect(AppSessionState.authenticated.isGuest, isFalse);
    });
  });

  group('the guest route allowlist is exact, not prefix', () {
    test('a closet CHILD is denied even though the root is allowed', () {
      expect(GuestCapabilities.allowsRoute(AppRoute.wtmCloset), isTrue);
      expect(GuestCapabilities.allowsRoute(AppRoute.wtmClosetAdd), isFalse);
      expect(GuestCapabilities.allowsRoute(AppRoute.wtmClosetItem), isFalse);
      expect(
        GuestCapabilities.allowsRoute(AppRoute.wtmClosetFixCutout),
        isFalse,
      );
    });

    test('a try-on CHILD is denied even though the root is allowed', () {
      expect(GuestCapabilities.allowsRoute(AppRoute.wtmMirror), isTrue);
      expect(
        GuestCapabilities.allowsRoute(AppRoute.wtmMirrorGarments),
        isFalse,
      );
      expect(GuestCapabilities.allowsRoute(AppRoute.wtmMirrorMode), isFalse);
      expect(
        GuestCapabilities.allowsRoute(AppRoute.wtmMirrorGenerating),
        isFalse,
      );
      expect(GuestCapabilities.allowsRoute(AppRoute.wtmMirrorResult), isFalse);
      expect(GuestCapabilities.allowsRoute(AppRoute.wtmMirrorAdjust), isFalse);
    });

    test('a profile CHILD is denied even though the tab root is allowed', () {
      expect(GuestCapabilities.allowsRoute(AppRoute.wtmProfile), isTrue);
      expect(GuestCapabilities.allowsRoute(AppRoute.wtmProfileEdit), isFalse);
      expect(GuestCapabilities.allowsRoute(AppRoute.wtmProfileSaved), isFalse);
      expect(GuestCapabilities.allowsRoute(AppRoute.wtmSettings), isFalse);
    });

    test('every private surface is denied', () {
      const denied = [
        AppRoute.wtmInbox,
        AppRoute.wtmSaved,
        AppRoute.wtmLooks,
        AppRoute.wtmTryOnHistory,
        AppRoute.wtmOutfits,
        AppRoute.wtmOutfitDetail,
        AppRoute.wtmStylist,
        AppRoute.wtmStylistLook,
        AppRoute.wtmMoodPlanner,
        AppRoute.wtmEvents,
        AppRoute.wtmBodyPhoto,
        AppRoute.wtmPaywall,
        AppRoute.wtmSocial,
        AppRoute.wtmPost,
        AppRoute.wtmCompose,
        AppRoute.wtmUser,
        AppRoute.wtmUserFollowers,
        AppRoute.wtmUserFollowing,
        AppRoute.wtmGiveawayCreate,
        AppRoute.wtmGiveawayChat,
        AppRoute.wtmNotifPrefs,
        AppRoute.wtmStyleMemory,
        AppRoute.wtmOnboarding,
        AppRoute.wtmReferral,
        AppRoute.wtmBrandStore,
      ];
      for (final route in denied) {
        expect(
          GuestCapabilities.allowsRoute(route),
          isFalse,
          reason: '$route must not be reachable by a guest',
        );
      }
    });

    test('the public browsing surfaces are allowed', () {
      const allowed = [
        AppRoute.wtmHome,
        AppRoute.wtmDiscover,
        AppRoute.wtmShopSearch,
        AppRoute.wtmShopBrowse,
        AppRoute.wtmProduct,
        AppRoute.wtmNewsroom,
        AppRoute.wtmArticle,
        AppRoute.wtmArticleWeb,
        AppRoute.wtmGiveaways,
        AppRoute.wtmGiveawayDetail,
      ];
      for (final route in allowed) {
        expect(
          GuestCapabilities.allowsRoute(route),
          isTrue,
          reason: '$route is public and must open for a guest',
        );
      }
    });

    test('an unknown route is denied (deny by default)', () {
      expect(GuestCapabilities.allowsRoute('/wtm/something-new'), isFalse);
      expect(GuestCapabilities.allowsRoute(''), isFalse);
      // Not fooled by a public prefix.
      expect(
        GuestCapabilities.allowsRoute('${AppRoute.wtmHome}/private'),
        isFalse,
      );
    });
  });

  group('the guest capability allowlist is pinned', () {
    test('exactly these capabilities are allowed, and no others', () {
      // If this fails because a value was ADDED to GuestCapability, the correct
      // fix is almost always to leave it denied and delete it from this list —
      // not to add it here. A capability reaches a guest only by a human
      // deciding it is safe without an account.
      expect(GuestCapabilities.allowed, {
        GuestCapability.viewHome,
        GuestCapability.previewMood,
        GuestCapability.browseShop,
        GuestCapability.searchProducts,
        GuestCapability.viewProductDetail,
        GuestCapability.openMerchantLink,
        GuestCapability.readNewsroom,
        GuestCapability.viewGiveawayInfo,
        GuestCapability.viewLegal,
        GuestCapability.viewTryOnExplainer,
      });
    });

    test('every allowed capability answers true', () {
      for (final capability in GuestCapabilities.allowed) {
        expect(GuestCapabilities.allows(capability), isTrue);
      }
    });
  });
}
