import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_consent_repository.dart';

/// Cached, account-scoped AI data-sharing consent.
///
/// Deliberately NOT autoDispose. This is read at the moment the user taps
/// Generate, and an autoDispose provider re-fetches (or hands back a null it is
/// still loading) exactly at that moment — the same footgun that once mis-fired
/// the Pro→paywall gate. Held for the session instead, invalidated explicitly on
/// sign-out so the next account on this device never inherits the previous one's
/// permission.
///
/// [build] does no I/O for the same reason: the gate must not depend on whether
/// a background fetch happened to have finished when the button was pressed. It
/// starts from "we do not know", and [current] is the one place that turns that
/// into a definite answer — a value, or a throw the caller can act on.
///
/// The cache is not an authority. The server re-checks on every submit, so a
/// client that somehow believed it had consent still gets
/// `AI_DATA_SHARING_CONSENT_REQUIRED` back with nothing shared and nothing
/// charged.
class AiConsentController extends AsyncNotifier<AiConsentState> {
  /// Whether [state] reflects a real server read, as opposed to the "unknown"
  /// seed. Without this, the seed is indistinguishable from a fetched "not
  /// granted" and the gate would never bother to ask the server at all.
  bool _fetched = false;

  @override
  AiConsentState build() => const AiConsentState.unknown();

  /// The current state — from cache if we have genuinely read it, else from the
  /// server.
  ///
  /// Throws on failure rather than answering "not granted": the caller must be
  /// able to tell "the user has not allowed this" from "we could not find out",
  /// because only the first of those is something a disclosure sheet can fix.
  Future<AiConsentState> current() async {
    final cached = state;
    if (_fetched && cached is AsyncData<AiConsentState>) return cached.value;
    final fresh = await ref.read(aiConsentRepositoryProvider).read();
    _fetched = true;
    state = AsyncData(fresh);
    return fresh;
  }

  /// Record an explicit grant. Returns the stored state so the caller proceeds
  /// only on a confirmed server write — never on optimistic local state, which
  /// would let a failed write become a render the user never authorised.
  Future<AiConsentState> grant() async {
    final granted = await ref.read(aiConsentRepositoryProvider).grant();
    _fetched = true;
    state = AsyncData(granted);
    return granted;
  }

  /// Withdraw consent. Future personal-photo AI requests ask again; nothing
  /// already stored is deleted (that is account deletion, a separate action).
  Future<AiConsentState> revoke() async {
    final revoked = await ref.read(aiConsentRepositoryProvider).revoke();
    _fetched = true;
    state = AsyncData(revoked);
    return revoked;
  }

  /// Re-read from the server — what the settings screen calls on open, because
  /// that screen claims to state the CURRENT status and a session-old cache is
  /// not good enough for a claim like that.
  ///
  /// A failed read lands in state as an error, which the screen renders as
  /// "Not allowed" — never briefly as "Allowed".
  Future<void> refresh() async {
    final next = await AsyncValue.guard(
      () => ref.read(aiConsentRepositoryProvider).read(),
    );
    _fetched = next is AsyncData<AiConsentState>;
    state = next;
  }
}

final aiConsentProvider =
    AsyncNotifierProvider<AiConsentController, AiConsentState>(
      AiConsentController.new,
    );
