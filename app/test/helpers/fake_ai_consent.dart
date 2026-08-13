import 'package:app/core/privacy/ai_consent_repository.dart';

/// In-memory [AiConsentRepository] for widget tests.
///
/// Defaults to ALREADY GRANTED so that tests about try-on, credits or
/// navigation keep testing those things instead of tripping over a consent
/// sheet. Tests that are about the gate itself start it ungranted.
class FakeAiConsentRepo implements AiConsentRepository {
  FakeAiConsentRepo({bool granted = true})
    : stored = granted
          ? const AiConsentState(
              granted: true,
              isCurrent: true,
              version: aiConsentVersion,
            )
          : const AiConsentState.unknown();

  AiConsentState stored;

  int reads = 0;
  int grants = 0;
  int revokes = 0;

  @override
  Future<AiConsentState> read() async {
    reads++;
    return stored;
  }

  @override
  Future<AiConsentState> grant() async {
    grants++;
    stored = const AiConsentState(
      granted: true,
      isCurrent: true,
      version: aiConsentVersion,
    );
    return stored;
  }

  @override
  Future<AiConsentState> revoke() async {
    revokes++;
    stored = const AiConsentState(
      granted: false,
      isCurrent: false,
      version: aiConsentVersion,
    );
    return stored;
  }
}
