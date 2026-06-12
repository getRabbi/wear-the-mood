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
  String get tryOnAvatarPrompt =>
      'Set up your avatar to try clothes on yourself';

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
  String get tryOnBlockedTitle => 'Can\'t use this photo';

  @override
  String get tryOnBlockedMessage =>
      'Please choose a different photo for try-on.';

  @override
  String get tryOnOutOfCredits => 'You\'re out of free try-ons for today.';

  @override
  String get navHome => 'Home';

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
  String get wardrobeDeleteTitle => 'Remove this piece?';

  @override
  String get wardrobeDeleteBody =>
      'It\'ll be removed from your closet. This can\'t be undone.';

  @override
  String get wardrobeDeleteConfirm => 'Remove';

  @override
  String get wardrobeDeleteCancel => 'Cancel';

  @override
  String get wardrobeDeleted => 'Removed from your closet';

  @override
  String get wardrobeDeleteError => 'Couldn\'t remove that. Please try again.';

  @override
  String get addItemTitle => 'Add a piece';

  @override
  String get addItemChoosePhoto => 'Add a photo of your piece';

  @override
  String get addItemCamera => 'Camera';

  @override
  String get addItemGallery => 'Gallery';

  @override
  String get addItemNameLabel => 'Name (optional)';

  @override
  String get addItemCategoryLabel => 'Category';

  @override
  String get addItemCatTops => 'Tops';

  @override
  String get addItemCatBottoms => 'Bottoms';

  @override
  String get addItemCatOuterwear => 'Outerwear';

  @override
  String get addItemCatShoes => 'Shoes';

  @override
  String get addItemCatAccessories => 'Accessories';

  @override
  String get addItemSave => 'Add to closet';

  @override
  String get addItemSaved => 'Added to your closet';

  @override
  String get addItemError => 'Couldn\'t add that. Please try again.';

  @override
  String get addItemPickError => 'Couldn\'t load that photo. Try another.';

  @override
  String get wardrobeProcessing => 'Processing';

  @override
  String get wardrobeSearchHint => 'Search your closet';

  @override
  String get wardrobeSearchEmptyTitle => 'No matches';

  @override
  String get wardrobeSearchEmptyMessage =>
      'Try a different word — a color, type or vibe.';

  @override
  String get commonClear => 'Clear';

  @override
  String get outfitsTitle => 'Outfits';

  @override
  String get outfitsEmptyTitle => 'No outfits yet';

  @override
  String get outfitsEmptyMessage =>
      'Combine pieces you own into looks you can reuse.';

  @override
  String get outfitsErrorTitle => 'Couldn\'t load your outfits';

  @override
  String get outfitsCreate => 'Create outfit';

  @override
  String get outfitsUntitled => 'Outfit';

  @override
  String outfitsPieceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pieces',
      one: '1 piece',
    );
    return '$_temp0';
  }

  @override
  String get outfitsDeleteTitle => 'Remove this outfit?';

  @override
  String get outfitsDeleteBody =>
      'It\'ll be removed from your saved looks. This can\'t be undone.';

  @override
  String get outfitsDeleteConfirm => 'Remove';

  @override
  String get outfitsDeleteCancel => 'Cancel';

  @override
  String get outfitsDeleted => 'Outfit removed';

  @override
  String get outfitsDeleteError => 'Couldn\'t remove that. Please try again.';

  @override
  String get createOutfitTitle => 'New outfit';

  @override
  String get createOutfitNameLabel => 'Name (optional)';

  @override
  String get createOutfitPickTitle => 'Pick pieces';

  @override
  String get createOutfitPickSubtitle =>
      'Tap items to add them to this outfit.';

  @override
  String get createOutfitSave => 'Save outfit';

  @override
  String get createOutfitSaved => 'Outfit saved';

  @override
  String get createOutfitError => 'Couldn\'t save. Please try again.';

  @override
  String get createOutfitNoItemsMessage =>
      'Add pieces to your closet first, then combine them into outfits.';

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
  String get stylistAppBarTitle => 'Today\'s stylist';

  @override
  String get stylistIntroTitle => 'What do I wear today?';

  @override
  String get stylistIntroBody =>
      'Get an outfit picked from your closet for today\'s weather and your taste.';

  @override
  String get stylistStyleMe => 'Style me';

  @override
  String get stylistStyleAgain => 'Style me again';

  @override
  String get stylistLoading => 'Putting together your look…';

  @override
  String get stylistErrorTitle => 'Couldn\'t style you';

  @override
  String get stylistEmptyTitle => 'Your closet is empty';

  @override
  String get stylistEmptyMessage =>
      'Add a few pieces and I\'ll put an outfit together for you.';

  @override
  String get navSocial => 'Community';

  @override
  String get feedTitle => 'Community';

  @override
  String get feedCompose => 'Share a look';

  @override
  String get feedEmptyTitle => 'No posts yet';

  @override
  String get feedEmptyMessage =>
      'Share your first look — your outfits, on the community.';

  @override
  String get feedErrorTitle => 'Couldn\'t load the feed';

  @override
  String get socialSomeone => 'Someone';

  @override
  String get socialFollow => 'Follow';

  @override
  String socialFollowing(String name) {
    return 'You\'re following $name';
  }

  @override
  String get socialActionError => 'Couldn\'t do that. Please try again.';

  @override
  String get postLike => 'Like';

  @override
  String get postDelete => 'Delete post';

  @override
  String get postDeleteTitle => 'Delete this post?';

  @override
  String get postDeleteBody =>
      'It\'ll be removed from the community. This can\'t be undone.';

  @override
  String get postDeleteConfirm => 'Delete';

  @override
  String get postDeleteCancel => 'Cancel';

  @override
  String get postDeleted => 'Post removed';

  @override
  String get postDeleteError => 'Couldn\'t remove that. Please try again.';

  @override
  String get postReport => 'Report post';

  @override
  String get socialBlock => 'Block user';

  @override
  String get reportTitle => 'Report this post?';

  @override
  String get reportBody =>
      'Our team will review it. Thanks for helping keep the community safe.';

  @override
  String get reportConfirm => 'Report';

  @override
  String get reported =>
      'Reported. Thanks for helping keep the community safe.';

  @override
  String get blockTitle => 'Block this user?';

  @override
  String get blockBody =>
      'You won\'t see their posts, and they won\'t see yours.';

  @override
  String get blockConfirm => 'Block';

  @override
  String get blocked => 'You won\'t see that user anymore';

  @override
  String get commentBlocked => 'That comment can\'t be posted.';

  @override
  String get composeTitle => 'Share a look';

  @override
  String get composeCaptionLabel => 'Say something (optional)';

  @override
  String get composePickOutfit => 'Choose an outfit to share';

  @override
  String get composeNoOutfitsTitle => 'No outfits yet';

  @override
  String get composeNoOutfits =>
      'Create an outfit first, then share it with the community.';

  @override
  String get composeShare => 'Share';

  @override
  String get composeShared => 'Shared to the community';

  @override
  String get composeError => 'Couldn\'t share. Please try again.';

  @override
  String get composeBlocked => 'That image can\'t be posted.';

  @override
  String get commentsTitle => 'Comments';

  @override
  String get commentsEmpty => 'No comments yet';

  @override
  String get commentsErrorTitle => 'Couldn\'t load comments';

  @override
  String get commentHint => 'Add a comment…';

  @override
  String get commentError => 'Couldn\'t post your comment.';

  @override
  String get feedChallenges => 'Challenges';

  @override
  String get challengesTitle => 'Challenges';

  @override
  String get challengesEmptyTitle => 'No challenges yet';

  @override
  String get challengesEmptyMessage =>
      'Check back soon — new style challenges drop here.';

  @override
  String get challengesErrorTitle => 'Couldn\'t load challenges';

  @override
  String challengeEntriesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
      zero: 'No entries yet',
    );
    return '$_temp0';
  }

  @override
  String get challengeJoinedBadge => 'Entered';

  @override
  String get challengeEntriesTitle => 'Entries';

  @override
  String get challengeEntriesEmpty => 'Be the first to enter this challenge.';

  @override
  String get challengeEnter => 'Enter this challenge';

  @override
  String get challengeErrorTitle => 'Couldn\'t load this challenge';

  @override
  String get challengeJoined => 'You\'re in! Your look is entered.';

  @override
  String get challengeJoinError =>
      'Couldn\'t enter the challenge. Please try again.';

  @override
  String composeEnterHeading(String title) {
    return 'Share a look to enter “$title”';
  }

  @override
  String get newsTitle => 'Fashion news';

  @override
  String get newsEmptyTitle => 'No news yet';

  @override
  String get newsEmptyMessage =>
      'Fresh fashion news and trends will land here soon.';

  @override
  String get newsErrorTitle => 'Couldn\'t load the news';

  @override
  String get newsOpenError => 'Couldn\'t open the article.';

  @override
  String get homeNewsTitle => 'Fashion news';

  @override
  String get homeNewsSubtitle => 'Trends, drops and industry buzz.';

  @override
  String get trendClosetAction => 'In your closet';

  @override
  String get newsShopAction => 'Shop this trend';

  @override
  String get trendClosetTitle => 'Your closet for this trend';

  @override
  String get trendClosetEmptyTitle => 'No matches yet';

  @override
  String get trendClosetEmptyMessage =>
      'Pieces from your wardrobe will appear here as your closet is analyzed.';

  @override
  String get trendClosetErrorTitle => 'Couldn\'t match your closet';

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
  String get profileAcceptableUse => 'Acceptable use policy';

  @override
  String get profileAvatar => 'Avatar & body';

  @override
  String get avatarTitle => 'Avatar & body';

  @override
  String get avatarLoadError => 'Couldn\'t load your profile';

  @override
  String get avatarConsentTitle => 'Use your photo for try-on';

  @override
  String get avatarConsentBody =>
      'We use your selfie only to show clothes on you. It\'s stored privately, never sold, and you can delete it anytime. Face and body data may be treated as biometric information.';

  @override
  String get avatarConsentAgree => 'I agree & continue';

  @override
  String get avatarConsentError =>
      'Couldn\'t record consent. Please try again.';

  @override
  String get avatarHeightLabel => 'Height (cm)';

  @override
  String get avatarBodyTypeLabel => 'Body type';

  @override
  String get avatarBodySlim => 'Slim';

  @override
  String get avatarBodyAverage => 'Average';

  @override
  String get avatarBodyAthletic => 'Athletic';

  @override
  String get avatarBodyCurvy => 'Curvy';

  @override
  String get avatarBodyPlus => 'Plus';

  @override
  String get avatarSave => 'Save';

  @override
  String get avatarSaved => 'Saved';

  @override
  String get avatarError => 'Couldn\'t save. Please try again.';

  @override
  String get avatarPrivacyNote =>
      'Stored privately. Delete anytime from your account.';

  @override
  String get profileLinkError => 'Couldn\'t open the link.';

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
  String get profileExportDone => 'Your data was copied to the clipboard';

  @override
  String get profileExportError =>
      'Couldn\'t export your data. Please try again.';

  @override
  String get profileDeleteDone => 'Your account and data have been deleted';

  @override
  String get profileDeleteError =>
      'Couldn\'t delete your account. Please try again.';

  @override
  String get paywallTitle => 'Unlock everything';

  @override
  String get paywallSubtitle =>
      'Your full style OS — unlimited try-ons, wardrobe and your AI stylist.';

  @override
  String get paywallFeatureUnlimited => 'Unlimited try-ons';

  @override
  String get paywallFeatureHd => 'HD results & video reels';

  @override
  String get paywallFeatureWardrobe => 'Unlimited wardrobe';

  @override
  String get paywallFeatureStylist => 'Advanced AI stylist';

  @override
  String get paywallFeaturePriority => 'Priority processing';

  @override
  String get paywallBestValue => 'BEST VALUE';

  @override
  String get paywallPerYear => 'per year';

  @override
  String get paywallPerMonth => 'per month';

  @override
  String paywallTrialNote(int days, String price) {
    return '$days-day free trial, then $price. Cancel anytime.';
  }

  @override
  String get paywallCta => 'Start free trial';

  @override
  String get paywallRestore => 'Restore purchases';

  @override
  String get paywallMaybeLater => 'Maybe later';

  @override
  String get paywallComingSoon => 'Subscriptions are coming soon.';

  @override
  String get paywallSeePlans => 'See plans';

  @override
  String get profilePremium => 'Fashion OS Premium';

  @override
  String creditsChipFree(int count) {
    return '$count free';
  }

  @override
  String creditsChipBalance(int count) {
    return '$count credits';
  }
}
