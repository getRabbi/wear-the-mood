import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The ONE place that decides what a platform is allowed to do.
///
/// Guest Mode exists to answer App Review guideline 5.1.1(v) on iOS/iPadOS: an
/// app may not force account creation to see content that does not need an
/// account. Google Play has no equivalent requirement, and the Android launch
/// experience is already shipped and stable — so Guest Mode is an **iOS-only**
/// capability, and Android must stay byte-for-byte what it is today.
///
/// Keeping that decision here, behind an injectable provider, is deliberate:
///
/// * a raw `Platform.isIOS` sprinkled through widgets is untestable (it reads
///   the real host, so an Android regression test can only ever assert what the
///   machine running it happens to be), and
/// * it drifts — the next feature copies the check, gets it subtly wrong, and
///   Android quietly grows a guest affordance nobody asked for.
///
/// Everything guest-related asks [PlatformCapabilities.guestModeSupported].
/// Tests override [platformCapabilitiesProvider] with a fixed platform instead
/// of mutating global state, so both platforms are provable on one machine.
@immutable
class PlatformCapabilities {
  const PlatformCapabilities({required this.platform, this.isWeb = false});

  /// The host platform. Injected rather than read from `defaultTargetPlatform`
  /// at the call site so tests can pin it.
  final TargetPlatform platform;

  /// Web builds report a [platform] (often iOS on Safari/iPadOS) that has
  /// nothing to do with the native app, so it is tracked separately and always
  /// denies Guest Mode.
  final bool isWeb;

  /// Reads the real host. The only call site is [platformCapabilitiesProvider].
  factory PlatformCapabilities.host() =>
      PlatformCapabilities(platform: defaultTargetPlatform, isWeb: kIsWeb);

  /// Whether this platform may offer "Continue as Guest".
  ///
  /// iOS and iPadOS only — iPadOS reports [TargetPlatform.iOS], which is what
  /// the App Review environment (iPad Air 11-inch, M3) runs. Android, web,
  /// macOS, Windows, Linux and Fuchsia all answer false, so the welcome screen
  /// never grows a guest button there and the guest router/service gates stay
  /// permanently closed.
  bool get guestModeSupported => !isWeb && platform == TargetPlatform.iOS;

  @override
  bool operator ==(Object other) =>
      other is PlatformCapabilities &&
      other.platform == platform &&
      other.isWeb == isWeb;

  @override
  int get hashCode => Object.hash(platform, isWeb);

  @override
  String toString() =>
      'PlatformCapabilities(platform: ${platform.name}, isWeb: $isWeb)';
}

/// The app-wide platform policy. Override in tests:
/// `platformCapabilitiesProvider.overrideWithValue(
///    const PlatformCapabilities(platform: TargetPlatform.android))`.
final platformCapabilitiesProvider = Provider<PlatformCapabilities>(
  (ref) => PlatformCapabilities.host(),
);

/// Convenience for the many read sites that only care about the one question.
/// Derived (not a second source of truth) so overriding the policy above moves
/// this too.
final guestModeSupportedProvider = Provider<bool>(
  (ref) => ref.watch(platformCapabilitiesProvider).guestModeSupported,
);
