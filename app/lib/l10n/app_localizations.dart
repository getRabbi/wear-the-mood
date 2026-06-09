import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// The application name, shown as the title.
  ///
  /// In en, this message translates to:
  /// **'Fashion OS'**
  String get appTitle;

  /// Temporary placeholder subtitle during early development.
  ///
  /// In en, this message translates to:
  /// **'Phase 0 — Foundations'**
  String get phase0Tagline;

  /// Label for retry buttons in error states.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonRetry;

  /// Generic add action label.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// Default title for an error state.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorGenericTitle;

  /// Default title for an empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get emptyGenericTitle;

  /// Home hero card title for the try-on feature.
  ///
  /// In en, this message translates to:
  /// **'Try it on'**
  String get homeTryOnTitle;

  /// Home hero card subtitle for the try-on feature.
  ///
  /// In en, this message translates to:
  /// **'See any piece on you before you buy.'**
  String get homeTryOnSubtitle;

  /// Home call-to-action that opens the try-on screen.
  ///
  /// In en, this message translates to:
  /// **'Start a try-on'**
  String get homeStartTryOn;

  /// App bar title on the try-on screen.
  ///
  /// In en, this message translates to:
  /// **'Try-on'**
  String get tryOnAppBarTitle;

  /// Heading above the garment picker.
  ///
  /// In en, this message translates to:
  /// **'Pick a piece'**
  String get tryOnPickTitle;

  /// Subtitle under the picker heading.
  ///
  /// In en, this message translates to:
  /// **'Choose something to see it on you.'**
  String get tryOnPickSubtitle;

  /// Primary button that starts a try-on.
  ///
  /// In en, this message translates to:
  /// **'Try it on'**
  String get tryOnCta;

  /// Progress label while the job is queued.
  ///
  /// In en, this message translates to:
  /// **'In the queue…'**
  String get tryOnQueued;

  /// Progress label while the job is processing.
  ///
  /// In en, this message translates to:
  /// **'Styling your look…'**
  String get tryOnProcessing;

  /// Title shown over a finished try-on result.
  ///
  /// In en, this message translates to:
  /// **'Your look'**
  String get tryOnResultTitle;

  /// Honest note shown while the stub provider is in use.
  ///
  /// In en, this message translates to:
  /// **'Preview uses a placeholder model until real try-on is enabled.'**
  String get tryOnResultStubNote;

  /// Action to start a new try-on after a result.
  ///
  /// In en, this message translates to:
  /// **'Try another'**
  String get tryOnTryAnother;

  /// Action to share a try-on result.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get tryOnShare;

  /// Error-state title on the try-on screen.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t finish the try-on'**
  String get tryOnErrorTitle;

  /// Message when the user has no credits left.
  ///
  /// In en, this message translates to:
  /// **'You\'re out of free try-ons for today.'**
  String get tryOnOutOfCredits;

  /// Compact credits chip — free daily try-ons remaining.
  ///
  /// In en, this message translates to:
  /// **'{count} free'**
  String creditsChipFree(int count);

  /// Compact credits chip — paid credit balance.
  ///
  /// In en, this message translates to:
  /// **'{count} credits'**
  String creditsChipBalance(int count);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
