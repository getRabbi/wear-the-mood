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
}
