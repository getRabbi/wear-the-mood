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
  String get tryOnShareComingSoon => 'Sharing is coming soon.';

  @override
  String get tryOnErrorTitle => 'Couldn\'t finish the try-on';

  @override
  String get tryOnOutOfCredits => 'You\'re out of free try-ons for today.';

  @override
  String get navWardrobe => 'Wardrobe';

  @override
  String get wardrobeEmptyTitle => 'Your closet is empty';

  @override
  String get wardrobeEmptyMessage =>
      'Add pieces you own to mix, match and try on.';

  @override
  String get wardrobeAdd => 'Add a piece';

  @override
  String get wardrobeComingSoon => 'Adding items is coming soon.';

  @override
  String get wardrobeErrorTitle => 'Couldn\'t load your closet';

  @override
  String get homeClosetTitle => 'Your closet';

  @override
  String get homeSeeAll => 'See all';

  @override
  String get homeClosetEmpty => 'No pieces yet';

  @override
  String get homeStylistTitle => 'Today\'s stylist';

  @override
  String get homeStylistSubtitle => 'Your daily outfit, picked for you.';

  @override
  String get homeComingSoon => 'Coming soon';

  @override
  String get onboardingValue1Title => 'See it on you';

  @override
  String get onboardingValue1Body => 'Try any look on yourself before you buy.';

  @override
  String get onboardingValue2Title => 'Your closet, digitized';

  @override
  String get onboardingValue2Body =>
      'Organize what you own and mix new outfits.';

  @override
  String get onboardingValue3Title => 'Your daily stylist';

  @override
  String get onboardingValue3Body =>
      'Outfit ideas from your wardrobe, the weather and your taste.';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingConsentTitle => 'Before we start';

  @override
  String get onboardingConsentBody =>
      'Fashion OS uses your photos and body details only to create your avatar and try-ons. Raw inputs are deleted after processing — never sold.';

  @override
  String get onboardingConsentAgree => 'I agree — let\'s go';

  @override
  String get authSignInTitle => 'Welcome back';

  @override
  String get authSignUpTitle => 'Create your account';

  @override
  String get authEmail => 'Email';

  @override
  String get authPassword => 'Password';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authSignUp => 'Sign up';

  @override
  String get authToggleToSignUp => 'New here? Create an account';

  @override
  String get authToggleToSignIn => 'Already have an account? Sign in';

  @override
  String get authGoogle => 'Continue with Google';

  @override
  String get authEmailInvalid => 'Enter a valid email.';

  @override
  String get authPasswordTooShort => 'Password must be at least 8 characters.';

  @override
  String get authGenericError => 'Couldn\'t sign you in. Please try again.';

  @override
  String get profileTitle => 'Profile';

  @override
  String profileSignedInAs(String email) {
    return 'Signed in as $email';
  }

  @override
  String get profileGuestTitle => 'You\'re browsing as a guest';

  @override
  String get profileGuestSubtitle => 'Sign in to save your wardrobe and looks.';

  @override
  String get profileSignIn => 'Sign in';

  @override
  String get profileSignOut => 'Sign out';

  @override
  String get profileSectionLegal => 'Privacy & legal';

  @override
  String get profileSectionAccount => 'Account';

  @override
  String get profilePrivacy => 'Privacy policy';

  @override
  String get profileTerms => 'Terms of service';

  @override
  String get profileExportData => 'Export my data';

  @override
  String get profileDeleteAccount => 'Delete account & data';

  @override
  String get profileDeleteConfirmTitle => 'Delete your account?';

  @override
  String get profileDeleteConfirmBody =>
      'This permanently removes your account, wardrobe and looks. This can\'t be undone.';

  @override
  String get profileCancel => 'Cancel';

  @override
  String get profileComingSoon => 'This is coming soon.';

  @override
  String creditsChipFree(int count) {
    return '$count free';
  }

  @override
  String creditsChipBalance(int count) {
    return '$count credits';
  }
}
