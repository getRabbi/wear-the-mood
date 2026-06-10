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

  /// Snackbar shown when tapping share before it's implemented.
  ///
  /// In en, this message translates to:
  /// **'Sharing is coming soon.'**
  String get tryOnShareComingSoon;

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

  /// Home tab label in the bottom navigation.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Wardrobe screen app-bar title.
  ///
  /// In en, this message translates to:
  /// **'Wardrobe'**
  String get navWardrobe;

  /// Empty-state title on the wardrobe screen.
  ///
  /// In en, this message translates to:
  /// **'Your closet is empty'**
  String get wardrobeEmptyTitle;

  /// Empty-state message on the wardrobe screen.
  ///
  /// In en, this message translates to:
  /// **'Add pieces you own to mix, match and try on.'**
  String get wardrobeEmptyMessage;

  /// Action to add a wardrobe item.
  ///
  /// In en, this message translates to:
  /// **'Add a piece'**
  String get wardrobeAdd;

  /// Snackbar when tapping add before it's implemented.
  ///
  /// In en, this message translates to:
  /// **'Adding items is coming soon.'**
  String get wardrobeComingSoon;

  /// Error-state title on the wardrobe screen.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your closet'**
  String get wardrobeErrorTitle;

  /// Title of the confirm dialog when removing a wardrobe item.
  ///
  /// In en, this message translates to:
  /// **'Remove this piece?'**
  String get wardrobeDeleteTitle;

  /// Body of the remove-item confirm dialog.
  ///
  /// In en, this message translates to:
  /// **'It\'ll be removed from your closet. This can\'t be undone.'**
  String get wardrobeDeleteBody;

  /// Confirm action to remove a wardrobe item.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get wardrobeDeleteConfirm;

  /// Cancel action in the remove-item dialog.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get wardrobeDeleteCancel;

  /// Snackbar confirming a wardrobe item was removed.
  ///
  /// In en, this message translates to:
  /// **'Removed from your closet'**
  String get wardrobeDeleted;

  /// Snackbar when removing a wardrobe item fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove that. Please try again.'**
  String get wardrobeDeleteError;

  /// App-bar title of the add-to-closet screen.
  ///
  /// In en, this message translates to:
  /// **'Add a piece'**
  String get addItemTitle;

  /// Prompt in the empty photo area.
  ///
  /// In en, this message translates to:
  /// **'Add a photo of your piece'**
  String get addItemChoosePhoto;

  /// Capture a photo with the camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get addItemCamera;

  /// Pick a photo from the gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get addItemGallery;

  /// Label for the item name field.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get addItemNameLabel;

  /// Heading above the category chips.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get addItemCategoryLabel;

  /// Wardrobe category.
  ///
  /// In en, this message translates to:
  /// **'Tops'**
  String get addItemCatTops;

  /// Wardrobe category.
  ///
  /// In en, this message translates to:
  /// **'Bottoms'**
  String get addItemCatBottoms;

  /// Wardrobe category.
  ///
  /// In en, this message translates to:
  /// **'Outerwear'**
  String get addItemCatOuterwear;

  /// Wardrobe category.
  ///
  /// In en, this message translates to:
  /// **'Shoes'**
  String get addItemCatShoes;

  /// Wardrobe category.
  ///
  /// In en, this message translates to:
  /// **'Accessories'**
  String get addItemCatAccessories;

  /// Button to save the new wardrobe item.
  ///
  /// In en, this message translates to:
  /// **'Add to closet'**
  String get addItemSave;

  /// Snackbar confirming the item was added.
  ///
  /// In en, this message translates to:
  /// **'Added to your closet'**
  String get addItemSaved;

  /// Snackbar when adding an item fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add that. Please try again.'**
  String get addItemError;

  /// Snackbar when picking/compressing a photo fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load that photo. Try another.'**
  String get addItemPickError;

  /// Badge on a wardrobe tile while its cutout is generating.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get wardrobeProcessing;

  /// Outfits screen title / wardrobe app-bar action to view outfits.
  ///
  /// In en, this message translates to:
  /// **'Outfits'**
  String get outfitsTitle;

  /// Empty-state title on the outfits screen.
  ///
  /// In en, this message translates to:
  /// **'No outfits yet'**
  String get outfitsEmptyTitle;

  /// Empty-state message on the outfits screen.
  ///
  /// In en, this message translates to:
  /// **'Combine pieces you own into looks you can reuse.'**
  String get outfitsEmptyMessage;

  /// Error-state title on the outfits screen.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your outfits'**
  String get outfitsErrorTitle;

  /// Action to start building a new outfit.
  ///
  /// In en, this message translates to:
  /// **'Create outfit'**
  String get outfitsCreate;

  /// Fallback label for an outfit saved without a name.
  ///
  /// In en, this message translates to:
  /// **'Outfit'**
  String get outfitsUntitled;

  /// Number of items in an outfit.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 piece} other{{count} pieces}}'**
  String outfitsPieceCount(int count);

  /// Title of the confirm dialog when removing an outfit.
  ///
  /// In en, this message translates to:
  /// **'Remove this outfit?'**
  String get outfitsDeleteTitle;

  /// Body of the remove-outfit confirm dialog.
  ///
  /// In en, this message translates to:
  /// **'It\'ll be removed from your saved looks. This can\'t be undone.'**
  String get outfitsDeleteBody;

  /// Confirm action to remove an outfit.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get outfitsDeleteConfirm;

  /// Cancel action in the remove-outfit dialog.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get outfitsDeleteCancel;

  /// Snackbar confirming an outfit was removed.
  ///
  /// In en, this message translates to:
  /// **'Outfit removed'**
  String get outfitsDeleted;

  /// Snackbar when removing an outfit fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove that. Please try again.'**
  String get outfitsDeleteError;

  /// App-bar title of the outfit builder screen.
  ///
  /// In en, this message translates to:
  /// **'New outfit'**
  String get createOutfitTitle;

  /// Label for the outfit name field.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get createOutfitNameLabel;

  /// Heading above the closet grid in the outfit builder.
  ///
  /// In en, this message translates to:
  /// **'Pick pieces'**
  String get createOutfitPickTitle;

  /// Subtitle explaining multi-select in the outfit builder.
  ///
  /// In en, this message translates to:
  /// **'Tap items to add them to this outfit.'**
  String get createOutfitPickSubtitle;

  /// Button to save the new outfit.
  ///
  /// In en, this message translates to:
  /// **'Save outfit'**
  String get createOutfitSave;

  /// Snackbar confirming the outfit was saved.
  ///
  /// In en, this message translates to:
  /// **'Outfit saved'**
  String get createOutfitSaved;

  /// Snackbar when saving an outfit fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save. Please try again.'**
  String get createOutfitError;

  /// Empty-state message in the outfit builder when the wardrobe is empty.
  ///
  /// In en, this message translates to:
  /// **'Add pieces to your closet first, then combine them into outfits.'**
  String get createOutfitNoItemsMessage;

  /// Home section heading for the wardrobe preview.
  ///
  /// In en, this message translates to:
  /// **'Your closet'**
  String get homeClosetTitle;

  /// Action linking a home section to its full screen.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get homeSeeAll;

  /// Home closet preview hint when the wardrobe is empty.
  ///
  /// In en, this message translates to:
  /// **'No pieces yet'**
  String get homeClosetEmpty;

  /// Home section heading for the daily stylist teaser.
  ///
  /// In en, this message translates to:
  /// **'Today\'s stylist'**
  String get homeStylistTitle;

  /// Home stylist teaser subtitle.
  ///
  /// In en, this message translates to:
  /// **'Your daily outfit, picked for you.'**
  String get homeStylistSubtitle;

  /// Badge on not-yet-built features.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get homeComingSoon;

  /// Onboarding value page 1 title.
  ///
  /// In en, this message translates to:
  /// **'See it on you'**
  String get onboardingValue1Title;

  /// Onboarding value page 1 body.
  ///
  /// In en, this message translates to:
  /// **'Try any look on yourself before you buy.'**
  String get onboardingValue1Body;

  /// Onboarding value page 2 title.
  ///
  /// In en, this message translates to:
  /// **'Your closet, digitized'**
  String get onboardingValue2Title;

  /// Onboarding value page 2 body.
  ///
  /// In en, this message translates to:
  /// **'Organize what you own and mix new outfits.'**
  String get onboardingValue2Body;

  /// Onboarding value page 3 title.
  ///
  /// In en, this message translates to:
  /// **'Your daily stylist'**
  String get onboardingValue3Title;

  /// Onboarding value page 3 body.
  ///
  /// In en, this message translates to:
  /// **'Outfit ideas from your wardrobe, the weather and your taste.'**
  String get onboardingValue3Body;

  /// Advance to the next onboarding page.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// Skip onboarding.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// Consent page title.
  ///
  /// In en, this message translates to:
  /// **'Before we start'**
  String get onboardingConsentTitle;

  /// Consent explanation (CLAUDE.md §10).
  ///
  /// In en, this message translates to:
  /// **'Fashion OS uses your photos and body details only to create your avatar and try-ons. Raw inputs are deleted after processing — never sold.'**
  String get onboardingConsentBody;

  /// Consent accept button.
  ///
  /// In en, this message translates to:
  /// **'I agree — let\'s go'**
  String get onboardingConsentAgree;

  /// Sign-in screen title.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get authSignInTitle;

  /// Sign-up screen title.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get authSignUpTitle;

  /// Email field label.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmail;

  /// Password field label.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// Sign-in submit button.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// Sign-up submit button.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get authSignUp;

  /// Switch to sign-up.
  ///
  /// In en, this message translates to:
  /// **'New here? Create an account'**
  String get authToggleToSignUp;

  /// Switch to sign-in.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get authToggleToSignIn;

  /// Google OAuth button.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get authGoogle;

  /// Email validation error.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email.'**
  String get authEmailInvalid;

  /// Password validation error.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters.'**
  String get authPasswordTooShort;

  /// Generic auth error.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sign you in. Please try again.'**
  String get authGenericError;

  /// Profile screen title.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// Profile header when signed in.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {email}'**
  String profileSignedInAs(String email);

  /// Profile header when signed out.
  ///
  /// In en, this message translates to:
  /// **'You\'re browsing as a guest'**
  String get profileGuestTitle;

  /// Profile guest subtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to save your wardrobe and looks.'**
  String get profileGuestSubtitle;

  /// Open the auth screen.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get profileSignIn;

  /// Sign out action.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get profileSignOut;

  /// Legal section header.
  ///
  /// In en, this message translates to:
  /// **'Privacy & legal'**
  String get profileSectionLegal;

  /// Account section header.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get profileSectionAccount;

  /// Privacy policy link.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get profilePrivacy;

  /// Terms link.
  ///
  /// In en, this message translates to:
  /// **'Terms of service'**
  String get profileTerms;

  /// Data export (GDPR, §10).
  ///
  /// In en, this message translates to:
  /// **'Export my data'**
  String get profileExportData;

  /// Account deletion (§10).
  ///
  /// In en, this message translates to:
  /// **'Delete account & data'**
  String get profileDeleteAccount;

  /// Delete confirm dialog title.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get profileDeleteConfirmTitle;

  /// Delete confirm dialog body.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes your account, wardrobe and looks. This can\'t be undone.'**
  String get profileDeleteConfirmBody;

  /// Cancel action.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get profileCancel;

  /// Placeholder snackbar for unbuilt profile actions.
  ///
  /// In en, this message translates to:
  /// **'This is coming soon.'**
  String get profileComingSoon;

  /// Snackbar after a successful data export (§10).
  ///
  /// In en, this message translates to:
  /// **'Your data was copied to the clipboard'**
  String get profileExportDone;

  /// Snackbar when data export fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t export your data. Please try again.'**
  String get profileExportError;

  /// Snackbar after a successful account deletion (§10).
  ///
  /// In en, this message translates to:
  /// **'Your account and data have been deleted'**
  String get profileDeleteDone;

  /// Snackbar when account deletion fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete your account. Please try again.'**
  String get profileDeleteError;

  /// Paywall hero title.
  ///
  /// In en, this message translates to:
  /// **'Unlock everything'**
  String get paywallTitle;

  /// Paywall hero subtitle.
  ///
  /// In en, this message translates to:
  /// **'Your full style OS — unlimited try-ons, wardrobe and your AI stylist.'**
  String get paywallSubtitle;

  /// Paywall feature.
  ///
  /// In en, this message translates to:
  /// **'Unlimited try-ons'**
  String get paywallFeatureUnlimited;

  /// Paywall feature.
  ///
  /// In en, this message translates to:
  /// **'HD results & video reels'**
  String get paywallFeatureHd;

  /// Paywall feature.
  ///
  /// In en, this message translates to:
  /// **'Unlimited wardrobe'**
  String get paywallFeatureWardrobe;

  /// Paywall feature.
  ///
  /// In en, this message translates to:
  /// **'Advanced AI stylist'**
  String get paywallFeatureStylist;

  /// Paywall feature.
  ///
  /// In en, this message translates to:
  /// **'Priority processing'**
  String get paywallFeaturePriority;

  /// Badge on the recommended plan.
  ///
  /// In en, this message translates to:
  /// **'BEST VALUE'**
  String get paywallBestValue;

  /// Annual plan period.
  ///
  /// In en, this message translates to:
  /// **'per year'**
  String get paywallPerYear;

  /// Monthly plan period.
  ///
  /// In en, this message translates to:
  /// **'per month'**
  String get paywallPerMonth;

  /// Trial + price line under the CTA.
  ///
  /// In en, this message translates to:
  /// **'{days}-day free trial, then {price}. Cancel anytime.'**
  String paywallTrialNote(int days, String price);

  /// Paywall primary CTA.
  ///
  /// In en, this message translates to:
  /// **'Start free trial'**
  String get paywallCta;

  /// Restore purchases action.
  ///
  /// In en, this message translates to:
  /// **'Restore purchases'**
  String get paywallRestore;

  /// Dismiss the paywall.
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get paywallMaybeLater;

  /// Placeholder until RevenueCat is wired.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions are coming soon.'**
  String get paywallComingSoon;

  /// Opens the paywall from an out-of-credits state.
  ///
  /// In en, this message translates to:
  /// **'See plans'**
  String get paywallSeePlans;

  /// Profile entry that opens the paywall.
  ///
  /// In en, this message translates to:
  /// **'Fashion OS Premium'**
  String get profilePremium;

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
