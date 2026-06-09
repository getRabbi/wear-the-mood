// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Fashion OS';

  @override
  String get phase0Tagline => 'Phase 0 — Foundations';

  @override
  String get commonRetry => 'Try again';

  @override
  String get commonAdd => 'Add';

  @override
  String get errorGenericTitle => 'Something went wrong';

  @override
  String get emptyGenericTitle => 'Nothing here yet';

  @override
  String get homeTryOnTitle => 'Try it on';

  @override
  String get homeTryOnSubtitle => 'See any piece on you before you buy.';

  @override
  String get homeStartTryOn => 'Start a try-on';

  @override
  String get tryOnAppBarTitle => 'Try-on';

  @override
  String get tryOnPickTitle => 'Pick a piece';

  @override
  String get tryOnPickSubtitle => 'Choose something to see it on you.';

  @override
  String get tryOnCta => 'Try it on';

  @override
  String get tryOnQueued => 'In the queue…';

  @override
  String get tryOnProcessing => 'Styling your look…';

  @override
  String get tryOnResultTitle => 'Your look';

  @override
  String get tryOnResultStubNote =>
      'Preview uses a placeholder model until real try-on is enabled.';

  @override
  String get tryOnTryAnother => 'Try another';

  @override
  String get tryOnShare => 'Share';

  @override
  String get tryOnErrorTitle => 'Couldn\'t finish the try-on';

  @override
  String get tryOnOutOfCredits => 'You\'re out of free try-ons for today.';

  @override
  String creditsChipFree(int count) {
    return '$count free';
  }

  @override
  String creditsChipBalance(int count) {
    return '$count credits';
  }
}
