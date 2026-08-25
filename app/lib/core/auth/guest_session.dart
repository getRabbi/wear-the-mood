import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../env/app_env.dart';
import '../platform/platform_capabilities.dart';
import 'auth_providers.dart';

/// Where the app stands with respect to identity — the single enum every gate
/// reads (CLAUDE.md §11, App Review 5.1.1(v)).
///
/// Guest is an explicit APPLICATION state. It is not a Supabase anonymous user,
/// a shadow account, a fake email or a server-side record of any kind: nothing
/// about a guest exists off the device. That is the whole point — a guest has
/// no account to attach photos, credits, jobs or writes to, which is why every
/// protected action must convert them first.
enum AppSessionState {
  /// Still resolving: Supabase is restoring a persisted session, or the guest
  /// flag has not been read off disk yet.
  ///
  /// **Never treat this as authenticated.** Everything protected is denied here
  /// exactly as it is for [signedOut] — the app fails closed while it does not
  /// yet know who it is talking to.
  unknown,

  /// No session and no guest choice → the welcome / sign-in gate.
  /// Identical permissions to [unknown]: deny everything protected.
  signedOut,

  /// An iOS user who chose "Continue as Guest". Public browsing only.
  guest,

  /// A real, verified Supabase session.
  authenticated;

  /// The only state that may perform a protected action. Written as an explicit
  /// switch rather than `== authenticated` so adding a state to this enum is a
  /// compile error here instead of a silent grant.
  bool get canPerformProtectedActions => switch (this) {
    AppSessionState.authenticated => true,
    AppSessionState.unknown ||
    AppSessionState.signedOut ||
    AppSessionState.guest => false,
  };

  /// Whether the app should render the public browsing experience.
  bool get isGuest => this == AppSessionState.guest;
}

/// Persists the device's guest choice. Deliberately tiny: one boolean, no user
/// data, no identifiers.
///
/// Stored in `flutter_secure_storage` because that is where this app already
/// keeps the equivalent `onboarding_complete` flag, so a guest is not thrown
/// back to the welcome screen on every launch (and the two flags cannot end up
/// in different stores with different lifetimes).
class GuestSessionRepository {
  GuestSessionRepository(this._storage);

  final FlutterSecureStorage _storage;

  /// Namespaced + versioned so a future shape change can be abandoned rather
  /// than migrated, matching the convention in `discover_local_store.dart`.
  static const storageKey = 'wtm.guest.v1.chosen';

  /// Never throws: a guest flag that cannot be read simply means "not a guest",
  /// which is the safe answer — the user sees the welcome screen and can choose
  /// again. Failing loudly here would block launch over a cache read.
  Future<bool> isGuest() async {
    try {
      return await _storage.read(key: storageKey) == 'true';
    } catch (error) {
      debugPrint('guest flag read failed: $error');
      return false;
    }
  }

  Future<void> setGuest() async {
    try {
      await _storage.write(key: storageKey, value: 'true');
    } catch (error) {
      // Best-effort. The in-memory state below still flips, so the current
      // session works; only the "remember me next launch" part is lost.
      debugPrint('guest flag write failed: $error');
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: storageKey);
    } catch (error) {
      debugPrint('guest flag clear failed: $error');
    }
  }
}

final guestSessionStorageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(),
);

final guestSessionRepositoryProvider = Provider<GuestSessionRepository>(
  (ref) => GuestSessionRepository(ref.watch(guestSessionStorageProvider)),
);

/// The device's guest choice, as a synchronously readable tri-state.
///
/// `null` means "not read yet" — which is what keeps a cold start from
/// momentarily reporting [AppSessionState.signedOut] (and flashing the welcome
/// screen) before the flag lands. It resolves to a real boolean once
/// [GuestSessionController.restore] completes.
class GuestSessionController extends Notifier<bool?> {
  @override
  bool? build() {
    // Off iOS the answer is known without touching the disk: guest state cannot
    // exist there, so it resolves SYNCHRONOUSLY and there is never an `unknown`
    // window. That is what keeps the Android cold start identical to today —
    // no extra state to settle, no extra frame to wait for.
    if (!ref.watch(guestModeSupportedProvider)) return false;

    // On iOS, read the persisted flag on the next microtask rather than from
    // inside `build`. A `state =` that lands mid-build is discarded (the value
    // returned below wins), which silently pinned this to `null` forever.
    Future.microtask(restore);
    return null;
  }

  /// Loads the persisted choice. Idempotent and safe to call again.
  Future<void> restore() async {
    // Guest Mode is iOS-only. On every other platform the flag is never read
    // and never written, so an Android build cannot enter guest state even if a
    // value somehow existed on disk.
    if (!ref.read(guestModeSupportedProvider)) {
      state = false;
      return;
    }
    final chosen = await ref.read(guestSessionRepositoryProvider).isGuest();
    state = chosen;
  }

  /// Records the explicit "Continue as Guest" tap. No-op off iOS.
  Future<void> enterGuest() async {
    if (!ref.read(guestModeSupportedProvider)) return;
    state = true;
    await ref.read(guestSessionRepositoryProvider).setGuest();
  }

  /// Drops guest state — on a successful sign-in (a real session always wins),
  /// and when the user explicitly leaves the guest experience.
  Future<void> exitGuest() async {
    state = false;
    // Off iOS the flag is never written, so there is nothing to delete and no
    // reason to open secure storage on a platform this feature does not exist
    // on. Sign-in on Android touches exactly what it touched before.
    if (!ref.read(guestModeSupportedProvider)) return;
    await ref.read(guestSessionRepositoryProvider).clear();
  }
}

final guestSessionProvider = NotifierProvider<GuestSessionController, bool?>(
  GuestSessionController.new,
);

/// **The** session state. Everything — router, UI, controllers, the network
/// guard — reads this one provider.
///
/// Precedence is fixed and not negotiable: a valid authenticated session always
/// beats a stale guest flag. A device that was a guest and has since signed in
/// is authenticated, full stop, even if the guest flag write failed to clear.
final appSessionProvider = Provider<AppSessionState>((ref) {
  // No Supabase configuration means no auth system exists in this build: no
  // session can be restored, none can be created, and — because entering guest
  // requires an explicit tap that this build has no way to reach — nobody can
  // be a guest either. That is the state of a widget test and of a local run
  // started without `--dart-define-from-file`.
  //
  // The guest gate exists to tell a guest apart from a member. Where neither
  // can exist it has nothing to separate, so it stands aside rather than
  // refusing work that has always been allowed; otherwise every controller test
  // in the suite would start failing on a gate that is not what it is testing.
  //
  // This is not a hole in production. A shipped build always has Supabase
  // configured — without it nobody can sign in and the app does not function —
  // and `isAuthenticatedProvider` is still false here regardless, so the ROUTER
  // gate is unchanged and no protected screen mounts in such a build anyway.
  //
  // Tests that are ABOUT the guest gate override this provider directly, which
  // is also why it is a plain (overridable) Provider rather than a computed
  // value hidden inside a notifier.
  if (!AppEnv.hasSupabaseConfig) return AppSessionState.authenticated;

  if (ref.watch(isAuthenticatedProvider)) return AppSessionState.authenticated;

  final guest = ref.watch(guestSessionProvider);
  // Flag not read yet → we genuinely do not know. Fail closed.
  if (guest == null) return AppSessionState.unknown;
  return guest ? AppSessionState.guest : AppSessionState.signedOut;
});

/// Sugar for the common read. Derived, so it can never disagree with the state.
final isGuestSessionProvider = Provider<bool>(
  (ref) => ref.watch(appSessionProvider).isGuest,
);
