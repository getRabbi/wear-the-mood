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

  /// Home greeting before noon.
  ///
  /// In en, this message translates to:
  /// **'GOOD MORNING'**
  String get homeGreetingMorning;

  /// Home greeting in the afternoon.
  ///
  /// In en, this message translates to:
  /// **'GOOD AFTERNOON'**
  String get homeGreetingAfternoon;

  /// Home greeting in the evening.
  ///
  /// In en, this message translates to:
  /// **'GOOD EVENING'**
  String get homeGreetingEvening;

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

  /// Title of the saved try-on results screen.
  ///
  /// In en, this message translates to:
  /// **'Try-on history'**
  String get tryonHistoryTitle;

  /// Error state on the try-on history screen.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your try-ons'**
  String get tryonHistoryError;

  /// Empty state title for try-on history.
  ///
  /// In en, this message translates to:
  /// **'No try-ons yet'**
  String get tryonHistoryEmptyTitle;

  /// Empty state message for try-on history.
  ///
  /// In en, this message translates to:
  /// **'Your try-on results will show up here.'**
  String get tryonHistoryEmptyMessage;

  /// CTA from the empty try-on history.
  ///
  /// In en, this message translates to:
  /// **'Start a try-on'**
  String get tryonHistoryStart;

  /// Heading above the garment picker.
  ///
  /// In en, this message translates to:
  /// **'Pick a piece'**
  String get tryOnPickTitle;

  /// Subtitle under the picker heading.
  ///
  /// In en, this message translates to:
  /// **'Pick a piece from your wardrobe to see it on you.'**
  String get tryOnPickSubtitle;

  /// Try-on picker empty state title when the closet has no items.
  ///
  /// In en, this message translates to:
  /// **'Your wardrobe is empty'**
  String get tryOnNoGarmentsTitle;

  /// Try-on picker empty state message.
  ///
  /// In en, this message translates to:
  /// **'Add clothes to your wardrobe, then try them on yourself.'**
  String get tryOnNoGarmentsMessage;

  /// Try-on empty state CTA to add wardrobe items.
  ///
  /// In en, this message translates to:
  /// **'Add clothes'**
  String get tryOnAddClothes;

  /// Nudge shown on the try-on picker when no avatar is set (§1).
  ///
  /// In en, this message translates to:
  /// **'Set up your avatar to try clothes on yourself'**
  String get tryOnAvatarPrompt;

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

  /// Title when a try-on input image is rejected by moderation (§19).
  ///
  /// In en, this message translates to:
  /// **'Can\'t use this photo'**
  String get tryOnBlockedTitle;

  /// Message when a try-on input image is blocked by moderation.
  ///
  /// In en, this message translates to:
  /// **'Please choose a different photo for try-on.'**
  String get tryOnBlockedMessage;

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

  /// Overlay title on a wardrobe tile while the cutout is generating.
  ///
  /// In en, this message translates to:
  /// **'Removing background'**
  String get wardrobeRemovingBackground;

  /// Overlay subtext while the cutout is generating.
  ///
  /// In en, this message translates to:
  /// **'Cleaning up your photo — just a few seconds'**
  String get wardrobeProcessingHint;

  /// Placeholder in the closet search field.
  ///
  /// In en, this message translates to:
  /// **'Search your closet'**
  String get wardrobeSearchHint;

  /// Empty-state title when a closet search returns nothing.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get wardrobeSearchEmptyTitle;

  /// Empty-state message for an empty search.
  ///
  /// In en, this message translates to:
  /// **'Try a different word — a color, type or vibe.'**
  String get wardrobeSearchEmptyMessage;

  /// Clear a search/input field.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

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

  /// App-bar title on the daily stylist screen.
  ///
  /// In en, this message translates to:
  /// **'Today\'s stylist'**
  String get stylistAppBarTitle;

  /// Idle-state heading on the stylist screen.
  ///
  /// In en, this message translates to:
  /// **'What do I wear today?'**
  String get stylistIntroTitle;

  /// Idle-state explanation on the stylist screen.
  ///
  /// In en, this message translates to:
  /// **'Get an outfit picked from your closet for today\'s weather and your taste.'**
  String get stylistIntroBody;

  /// Primary button that requests a stylist suggestion.
  ///
  /// In en, this message translates to:
  /// **'Style me'**
  String get stylistStyleMe;

  /// Action to request another suggestion after one is shown.
  ///
  /// In en, this message translates to:
  /// **'Style me again'**
  String get stylistStyleAgain;

  /// Progress label while the stylist is thinking.
  ///
  /// In en, this message translates to:
  /// **'Putting together your look…'**
  String get stylistLoading;

  /// Error-state title on the stylist screen.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t style you'**
  String get stylistErrorTitle;

  /// Empty-state title when the stylist has no pieces to use.
  ///
  /// In en, this message translates to:
  /// **'Your closet is empty'**
  String get stylistEmptyTitle;

  /// Empty-state message guiding the user to add wardrobe items.
  ///
  /// In en, this message translates to:
  /// **'Add a few pieces and I\'ll put an outfit together for you.'**
  String get stylistEmptyMessage;

  /// Social/feed tab label in the bottom navigation.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get navSocial;

  /// App-bar title on the community feed.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get feedTitle;

  /// Title of the combined Community + Newsroom screen.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get communityTitle;

  /// Tab label for the social feed.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get communityTabFeed;

  /// Tab label for the fashion news feed.
  ///
  /// In en, this message translates to:
  /// **'Newsroom'**
  String get communityTabNews;

  /// Title of the monthly community leaderboard.
  ///
  /// In en, this message translates to:
  /// **'Style leaderboard'**
  String get leaderboardTitle;

  /// Subtitle on the leaderboard banner.
  ///
  /// In en, this message translates to:
  /// **'Win a free month of Premium'**
  String get leaderboardBannerSubtitle;

  /// Prize line on the leaderboard.
  ///
  /// In en, this message translates to:
  /// **'Top stylist this month wins a free month of Premium'**
  String get leaderboardPrize;

  /// Countdown to the month-end winner.
  ///
  /// In en, this message translates to:
  /// **'{days} days left this month'**
  String leaderboardDaysLeft(int days);

  /// Label for the caller's rank card.
  ///
  /// In en, this message translates to:
  /// **'Your rank'**
  String get leaderboardYourRank;

  /// Shown when the caller has no score yet.
  ///
  /// In en, this message translates to:
  /// **'Share a look to join the board'**
  String get leaderboardYouUnranked;

  /// A score with its unit.
  ///
  /// In en, this message translates to:
  /// **'{score} pts'**
  String leaderboardScore(int score);

  /// Marks the caller's own row in the leaderboard.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get leaderboardYouLabel;

  /// Empty leaderboard state.
  ///
  /// In en, this message translates to:
  /// **'No scores yet this month — be the first!'**
  String get leaderboardEmpty;

  /// Leaderboard error state.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the leaderboard'**
  String get leaderboardError;

  /// Heading for the past-winners list.
  ///
  /// In en, this message translates to:
  /// **'Past winners'**
  String get leaderboardPastWinners;

  /// Action that opens the post composer.
  ///
  /// In en, this message translates to:
  /// **'Share a look'**
  String get feedCompose;

  /// Empty-state title on the feed.
  ///
  /// In en, this message translates to:
  /// **'No posts yet'**
  String get feedEmptyTitle;

  /// Empty-state message on the feed.
  ///
  /// In en, this message translates to:
  /// **'Share your first look — your outfits, on the community.'**
  String get feedEmptyMessage;

  /// Error-state title on the feed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the feed'**
  String get feedErrorTitle;

  /// Fallback name when an author has no display name.
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get socialSomeone;

  /// Action to follow a post's author.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get socialFollow;

  /// Snackbar after following an author.
  ///
  /// In en, this message translates to:
  /// **'You\'re following {name}'**
  String socialFollowing(String name);

  /// Generic social action failure snackbar.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t do that. Please try again.'**
  String get socialActionError;

  /// Semantic label for the like action.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get postLike;

  /// Overflow action to delete the user's own post.
  ///
  /// In en, this message translates to:
  /// **'Delete post'**
  String get postDelete;

  /// Delete-post confirm dialog title.
  ///
  /// In en, this message translates to:
  /// **'Delete this post?'**
  String get postDeleteTitle;

  /// Delete-post confirm dialog body.
  ///
  /// In en, this message translates to:
  /// **'It\'ll be removed from the community. This can\'t be undone.'**
  String get postDeleteBody;

  /// Confirm deleting a post.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get postDeleteConfirm;

  /// Cancel deleting a post.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get postDeleteCancel;

  /// Snackbar confirming a post was removed.
  ///
  /// In en, this message translates to:
  /// **'Post removed'**
  String get postDeleted;

  /// Snackbar when deleting a post fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove that. Please try again.'**
  String get postDeleteError;

  /// Overflow action to report a post (§19).
  ///
  /// In en, this message translates to:
  /// **'Report post'**
  String get postReport;

  /// Overflow action to block a post's author (§19).
  ///
  /// In en, this message translates to:
  /// **'Block user'**
  String get socialBlock;

  /// Report confirm dialog title.
  ///
  /// In en, this message translates to:
  /// **'Report this post?'**
  String get reportTitle;

  /// Report confirm dialog body.
  ///
  /// In en, this message translates to:
  /// **'Our team will review it. Thanks for helping keep the community safe.'**
  String get reportBody;

  /// Confirm filing a report.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get reportConfirm;

  /// Snackbar after a report is filed.
  ///
  /// In en, this message translates to:
  /// **'Reported. Thanks for helping keep the community safe.'**
  String get reported;

  /// Block confirm dialog title.
  ///
  /// In en, this message translates to:
  /// **'Block this user?'**
  String get blockTitle;

  /// Block confirm dialog body.
  ///
  /// In en, this message translates to:
  /// **'You won\'t see their posts, and they won\'t see yours.'**
  String get blockBody;

  /// Confirm blocking a user.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get blockConfirm;

  /// Snackbar after blocking a user.
  ///
  /// In en, this message translates to:
  /// **'You won\'t see that user anymore'**
  String get blocked;

  /// Snackbar when a comment is blocked by moderation (§19).
  ///
  /// In en, this message translates to:
  /// **'That comment can\'t be posted.'**
  String get commentBlocked;

  /// App-bar title of the post composer.
  ///
  /// In en, this message translates to:
  /// **'Share a look'**
  String get composeTitle;

  /// Caption field label in the composer.
  ///
  /// In en, this message translates to:
  /// **'Say something (optional)'**
  String get composeCaptionLabel;

  /// Heading above the outfit picker in the composer.
  ///
  /// In en, this message translates to:
  /// **'Choose an outfit to share'**
  String get composePickOutfit;

  /// Composer source toggle: upload any photo.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get composeSourcePhoto;

  /// Composer source toggle: share a saved outfit.
  ///
  /// In en, this message translates to:
  /// **'Outfit'**
  String get composeSourceOutfit;

  /// Tags field label in the composer.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get composeTagsLabel;

  /// Tags field hint in the composer.
  ///
  /// In en, this message translates to:
  /// **'e.g. ootd, streetwear'**
  String get composeTagsHint;

  /// Composer empty-state title when there are no outfits.
  ///
  /// In en, this message translates to:
  /// **'No outfits yet'**
  String get composeNoOutfitsTitle;

  /// Composer empty-state message.
  ///
  /// In en, this message translates to:
  /// **'Create an outfit first, then share it with the community.'**
  String get composeNoOutfits;

  /// Button that publishes the post.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get composeShare;

  /// Snackbar after a post is published.
  ///
  /// In en, this message translates to:
  /// **'Shared to the community'**
  String get composeShared;

  /// Snackbar when publishing a post fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t share. Please try again.'**
  String get composeError;

  /// Snackbar when a post image is blocked by moderation (§19).
  ///
  /// In en, this message translates to:
  /// **'That image can\'t be posted.'**
  String get composeBlocked;

  /// Title of the comments sheet.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get commentsTitle;

  /// Empty-state in the comments sheet.
  ///
  /// In en, this message translates to:
  /// **'No comments yet'**
  String get commentsEmpty;

  /// Error-state title in the comments sheet.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load comments'**
  String get commentsErrorTitle;

  /// Placeholder in the comment input.
  ///
  /// In en, this message translates to:
  /// **'Add a comment…'**
  String get commentHint;

  /// Snackbar when adding a comment fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t post your comment.'**
  String get commentError;

  /// Feed app-bar action that opens style challenges.
  ///
  /// In en, this message translates to:
  /// **'Challenges'**
  String get feedChallenges;

  /// Challenges screen title.
  ///
  /// In en, this message translates to:
  /// **'Challenges'**
  String get challengesTitle;

  /// Empty-state title on the challenges list.
  ///
  /// In en, this message translates to:
  /// **'No challenges yet'**
  String get challengesEmptyTitle;

  /// Empty-state message on the challenges list.
  ///
  /// In en, this message translates to:
  /// **'Check back soon — new style challenges drop here.'**
  String get challengesEmptyMessage;

  /// Error-state title on the challenges list.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load challenges'**
  String get challengesErrorTitle;

  /// Entry count on a challenge card.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No entries yet} =1{1 entry} other{{count} entries}}'**
  String challengeEntriesCount(int count);

  /// Badge on a challenge the user has already entered.
  ///
  /// In en, this message translates to:
  /// **'Entered'**
  String get challengeJoinedBadge;

  /// Heading above a challenge's entries gallery.
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get challengeEntriesTitle;

  /// Empty-state when a challenge has no entries.
  ///
  /// In en, this message translates to:
  /// **'Be the first to enter this challenge.'**
  String get challengeEntriesEmpty;

  /// CTA that opens the composer to enter a challenge.
  ///
  /// In en, this message translates to:
  /// **'Enter this challenge'**
  String get challengeEnter;

  /// Error-state title on the challenge detail screen.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this challenge'**
  String get challengeErrorTitle;

  /// Snackbar after successfully entering a challenge.
  ///
  /// In en, this message translates to:
  /// **'You\'re in! Your look is entered.'**
  String get challengeJoined;

  /// Snackbar when entering a challenge fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t enter the challenge. Please try again.'**
  String get challengeJoinError;

  /// Composer heading when sharing a look to enter a challenge.
  ///
  /// In en, this message translates to:
  /// **'Share a look to enter “{title}”'**
  String composeEnterHeading(String title);

  /// News feed screen title.
  ///
  /// In en, this message translates to:
  /// **'Fashion news'**
  String get newsTitle;

  /// Empty-state title on the news feed.
  ///
  /// In en, this message translates to:
  /// **'No news yet'**
  String get newsEmptyTitle;

  /// Empty-state message on the news feed.
  ///
  /// In en, this message translates to:
  /// **'Fresh fashion news and trends will land here soon.'**
  String get newsEmptyMessage;

  /// Error-state title on the news feed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the news'**
  String get newsErrorTitle;

  /// Snackbar when an article link fails to open.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the article.'**
  String get newsOpenError;

  /// Home teaser title for the news feed.
  ///
  /// In en, this message translates to:
  /// **'Fashion news'**
  String get homeNewsTitle;

  /// Home teaser subtitle for the news feed.
  ///
  /// In en, this message translates to:
  /// **'Trends, drops and industry buzz.'**
  String get homeNewsSubtitle;

  /// News card action that shows matching wardrobe pieces (§24).
  ///
  /// In en, this message translates to:
  /// **'In your closet'**
  String get trendClosetAction;

  /// News card action that opens an affiliate search for the trend (§18).
  ///
  /// In en, this message translates to:
  /// **'Shop this trend'**
  String get newsShopAction;

  /// Wardrobe item action that logs a wear (§24).
  ///
  /// In en, this message translates to:
  /// **'Mark as worn today'**
  String get wardrobeMarkWorn;

  /// Wardrobe item action that removes the piece.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get wardrobeRemove;

  /// Snackbar after logging a wear.
  ///
  /// In en, this message translates to:
  /// **'Logged a wear'**
  String get wardrobeWornLogged;

  /// Generic wardrobe action failure snackbar.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t do that. Please try again.'**
  String get wardrobeActionError;

  /// Wardrobe analytics screen title (§24).
  ///
  /// In en, this message translates to:
  /// **'Wardrobe insights'**
  String get insightsTitle;

  /// Error-state title on the insights screen.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your insights'**
  String get insightsErrorTitle;

  /// Empty-state title on the insights screen.
  ///
  /// In en, this message translates to:
  /// **'No insights yet'**
  String get insightsEmptyTitle;

  /// Empty-state message on the insights screen.
  ///
  /// In en, this message translates to:
  /// **'Add pieces and log wears to see your cost-per-wear.'**
  String get insightsEmptyMessage;

  /// Insights stat label: number of items.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get insightsItems;

  /// Insights stat label: total spend.
  ///
  /// In en, this message translates to:
  /// **'Total spend'**
  String get insightsSpend;

  /// Insights stat label: total wears.
  ///
  /// In en, this message translates to:
  /// **'Total wears'**
  String get insightsTotalWears;

  /// Insights stat label: average cost per wear.
  ///
  /// In en, this message translates to:
  /// **'Avg / wear'**
  String get insightsAvgPerWear;

  /// Insights stat label: count of never-worn items.
  ///
  /// In en, this message translates to:
  /// **'Unworn'**
  String get insightsNeverWornCount;

  /// Highlight label: most-worn piece.
  ///
  /// In en, this message translates to:
  /// **'Most worn'**
  String get insightsMostWorn;

  /// Highlight label: lowest cost-per-wear piece.
  ///
  /// In en, this message translates to:
  /// **'Best value'**
  String get insightsBestValue;

  /// Highlight label: priciest under-used piece.
  ///
  /// In en, this message translates to:
  /// **'Biggest waste'**
  String get insightsBiggestWaste;

  /// Trailing label when a highlighted piece was never worn.
  ///
  /// In en, this message translates to:
  /// **'Never worn'**
  String get insightsNeverWorn;

  /// Cost-per-wear trailing value, e.g. $2.00/wear.
  ///
  /// In en, this message translates to:
  /// **'{value}/wear'**
  String insightsPerWear(String value);

  /// Wear count for a highlighted piece.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 wear} other{{count} wears}}'**
  String insightsWears(int count);

  /// Heading above closet-gap suggestions (§24).
  ///
  /// In en, this message translates to:
  /// **'Fill the gaps'**
  String get insightsGapsTitle;

  /// Subtitle on a closet-gap card.
  ///
  /// In en, this message translates to:
  /// **'Not in your closet yet'**
  String get insightsGapMissing;

  /// Closet-gap action that opens a shop-the-look link (§18).
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get insightsGapShop;

  /// Snackbar when a closet-gap shop link fails to open.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the shop link.'**
  String get insightsGapShopError;

  /// Profile entry that opens the referral screen (§24).
  ///
  /// In en, this message translates to:
  /// **'Invite friends'**
  String get profileInvite;

  /// Referral screen title.
  ///
  /// In en, this message translates to:
  /// **'Invite friends'**
  String get referralTitle;

  /// Referral screen headline.
  ///
  /// In en, this message translates to:
  /// **'Give credits, get credits'**
  String get referralHeadline;

  /// Referral value proposition.
  ///
  /// In en, this message translates to:
  /// **'You and a friend each get {credits} free try-ons when they join with your code.'**
  String referralSubtitle(int credits);

  /// Label above the user's referral code.
  ///
  /// In en, this message translates to:
  /// **'Your code'**
  String get referralYourCode;

  /// Button that copies the invite to share.
  ///
  /// In en, this message translates to:
  /// **'Share invite'**
  String get referralShare;

  /// Snackbar after copying the invite.
  ///
  /// In en, this message translates to:
  /// **'Invite copied — paste it to a friend'**
  String get referralCopied;

  /// How many friends the user has referred.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 friend has joined} other{{count} friends have joined}}'**
  String referralCount(int count);

  /// Heading above the redeem field.
  ///
  /// In en, this message translates to:
  /// **'Have a code?'**
  String get referralRedeemTitle;

  /// Placeholder in the redeem field.
  ///
  /// In en, this message translates to:
  /// **'Enter a referral code'**
  String get referralRedeemHint;

  /// Redeem button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Redeem'**
  String get referralRedeem;

  /// Snackbar after a successful redemption.
  ///
  /// In en, this message translates to:
  /// **'You earned {credits} credits!'**
  String referralRedeemSuccess(int credits);

  /// Snackbar when redemption fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t redeem that code. It may be invalid, your own, or already used.'**
  String get referralRedeemError;

  /// Error-state title on the referral screen.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load referrals'**
  String get referralErrorTitle;

  /// The shareable invite message.
  ///
  /// In en, this message translates to:
  /// **'Join me on Fashion OS — try clothes on before you buy. Use my code {code} when you sign up and we both get free try-ons!'**
  String referralShareText(String code);

  /// Home teaser title for the packing planner (§24).
  ///
  /// In en, this message translates to:
  /// **'Pack for a trip'**
  String get homePackingTitle;

  /// Home teaser subtitle for the packing planner.
  ///
  /// In en, this message translates to:
  /// **'A smart packing list from your closet.'**
  String get homePackingSubtitle;

  /// Packing planner screen title.
  ///
  /// In en, this message translates to:
  /// **'Packing planner'**
  String get packingTitle;

  /// Heading above the day selector.
  ///
  /// In en, this message translates to:
  /// **'Trip length'**
  String get packingDaysLabel;

  /// Trip length option.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String packingDays(int count);

  /// Occasion field label in the packing planner.
  ///
  /// In en, this message translates to:
  /// **'Occasion (optional) — beach, work trip…'**
  String get packingOccasionHint;

  /// Button that generates the packing list.
  ///
  /// In en, this message translates to:
  /// **'Pack my bag'**
  String get packingCta;

  /// Idle hint before a packing list is generated.
  ///
  /// In en, this message translates to:
  /// **'Pick your trip length and I\'ll pack a versatile list from your closet.'**
  String get packingIntro;

  /// Error-state title on the packing planner.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t plan your trip'**
  String get packingErrorTitle;

  /// Calendar autopilot screen title (§24).
  ///
  /// In en, this message translates to:
  /// **'Plan my week'**
  String get calendarTitle;

  /// Intro on the calendar autopilot screen.
  ///
  /// In en, this message translates to:
  /// **'Add your upcoming events and I\'ll suggest an outfit for each.'**
  String get calendarIntro;

  /// Hint in the add-event field.
  ///
  /// In en, this message translates to:
  /// **'Add an event — e.g. Work meeting, Dinner'**
  String get calendarAddHint;

  /// Button to import device-calendar events (gated).
  ///
  /// In en, this message translates to:
  /// **'Import from calendar'**
  String get calendarImport;

  /// Snackbar — device-calendar import not wired yet.
  ///
  /// In en, this message translates to:
  /// **'Calendar import is coming soon.'**
  String get calendarImportSoon;

  /// Button that generates an outfit per event.
  ///
  /// In en, this message translates to:
  /// **'Plan my outfits'**
  String get calendarPlan;

  /// Error-state title on the calendar autopilot screen.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t plan your week'**
  String get calendarErrorTitle;

  /// Title of the trend-to-closet matches sheet.
  ///
  /// In en, this message translates to:
  /// **'Your closet for this trend'**
  String get trendClosetTitle;

  /// Empty-state title in the trend-to-closet sheet.
  ///
  /// In en, this message translates to:
  /// **'No matches yet'**
  String get trendClosetEmptyTitle;

  /// Empty-state message in the trend-to-closet sheet.
  ///
  /// In en, this message translates to:
  /// **'Pieces from your wardrobe will appear here as your closet is analyzed.'**
  String get trendClosetEmptyMessage;

  /// Error-state title in the trend-to-closet sheet.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t match your closet'**
  String get trendClosetErrorTitle;

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

  /// Sign-in screen subtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your existing account to continue.'**
  String get authSignInSubtitle;

  /// Sign-up screen subtitle.
  ///
  /// In en, this message translates to:
  /// **'New here? Create an account with your email to get started.'**
  String get authSignUpSubtitle;

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

  /// Confirm-password field label (sign-up).
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get authConfirmPassword;

  /// Confirm-password mismatch error.
  ///
  /// In en, this message translates to:
  /// **'Passwords don\'t match.'**
  String get authPasswordMismatch;

  /// Sign-in submit button.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// Sign-up mode tab label.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get authSignUp;

  /// Sign-in submit button.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get authSignInCta;

  /// Sign-up submit button.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authSignUpCta;

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

  /// Shown after sign-up when email confirmation is required.
  ///
  /// In en, this message translates to:
  /// **'Account created — check your email to confirm, then sign in.'**
  String get authCheckEmail;

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

  /// Acceptable-use policy link (§19).
  ///
  /// In en, this message translates to:
  /// **'Acceptable use policy'**
  String get profileAcceptableUse;

  /// Profile tile to set up the try-on body photo + body data (§1).
  ///
  /// In en, this message translates to:
  /// **'Body & try-on photo'**
  String get profileAvatar;

  /// Try-on photo + body data capture screen title.
  ///
  /// In en, this message translates to:
  /// **'Body & try-on photo'**
  String get avatarTitle;

  /// Guidance on the avatar capture step so the photo works for FASHN try-on.
  ///
  /// In en, this message translates to:
  /// **'For try-on, use a full-body photo — stand facing the camera in good light with a plain background. A face-only selfie won\'t work for trying on clothes.'**
  String get avatarPhotoTip;

  /// Error state on the avatar screen.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your profile'**
  String get avatarLoadError;

  /// Biometric consent gate title (§10).
  ///
  /// In en, this message translates to:
  /// **'Use your photo for try-on'**
  String get avatarConsentTitle;

  /// Biometric consent explanation, v2 — now covers richer body data (§10).
  ///
  /// In en, this message translates to:
  /// **'We use your photo and the body details you share only to show clothes on you and suggest outfits. They\'re stored privately, never sold, and you can delete them anytime. Face and body data may be treated as biometric information.'**
  String get avatarConsentBody;

  /// Accept biometric consent.
  ///
  /// In en, this message translates to:
  /// **'I agree & continue'**
  String get avatarConsentAgree;

  /// Snackbar when recording consent fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t record consent. Please try again.'**
  String get avatarConsentError;

  /// Label for the height field (unit chosen by the cm/ft toggle).
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get avatarHeightLabel;

  /// Heading for body-type chips.
  ///
  /// In en, this message translates to:
  /// **'Body type'**
  String get avatarBodyTypeLabel;

  /// Body type.
  ///
  /// In en, this message translates to:
  /// **'Slim'**
  String get avatarBodySlim;

  /// Body type.
  ///
  /// In en, this message translates to:
  /// **'Average'**
  String get avatarBodyAverage;

  /// Body type.
  ///
  /// In en, this message translates to:
  /// **'Athletic'**
  String get avatarBodyAthletic;

  /// Body type.
  ///
  /// In en, this message translates to:
  /// **'Curvy'**
  String get avatarBodyCurvy;

  /// Body type.
  ///
  /// In en, this message translates to:
  /// **'Plus'**
  String get avatarBodyPlus;

  /// Save the avatar + body data.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get avatarSave;

  /// Snackbar after saving the avatar/body.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get avatarSaved;

  /// Snackbar when saving the avatar/body fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save. Please try again.'**
  String get avatarError;

  /// Privacy reassurance under the avatar form (§10).
  ///
  /// In en, this message translates to:
  /// **'Stored privately. Delete anytime from your account.'**
  String get avatarPrivacyNote;

  /// Section header for the try-on body photo.
  ///
  /// In en, this message translates to:
  /// **'Try-on photo'**
  String get avatarSectionPhoto;

  /// Section header for body measurements/attributes.
  ///
  /// In en, this message translates to:
  /// **'Body details'**
  String get avatarSectionBody;

  /// Heading of the photo-guidance card.
  ///
  /// In en, this message translates to:
  /// **'Take the perfect try-on photo'**
  String get avatarGuideTitle;

  /// Subtitle of the photo-guidance card.
  ///
  /// In en, this message translates to:
  /// **'We place clothes on this photo, so your whole body must be visible.'**
  String get avatarGuideSubtitle;

  /// Photo do #1.
  ///
  /// In en, this message translates to:
  /// **'Stand straight — head to feet in frame'**
  String get avatarGuideDo1;

  /// Photo do #2.
  ///
  /// In en, this message translates to:
  /// **'Plain background, good lighting'**
  String get avatarGuideDo2;

  /// Photo do #3.
  ///
  /// In en, this message translates to:
  /// **'Face the camera, arms slightly away'**
  String get avatarGuideDo3;

  /// Photo do #4.
  ///
  /// In en, this message translates to:
  /// **'Fitted clothes, not baggy'**
  String get avatarGuideDo4;

  /// Photo do #5.
  ///
  /// In en, this message translates to:
  /// **'Just you — one person'**
  String get avatarGuideDo5;

  /// Photo don'ts line.
  ///
  /// In en, this message translates to:
  /// **'Avoid close-ups, cut-off mirror shots, or group photos.'**
  String get avatarGuideDont;

  /// Supported image formats note.
  ///
  /// In en, this message translates to:
  /// **'Works with JPG, PNG, and iPhone (HEIC) photos.'**
  String get avatarGuideFormats;

  /// Caption under the good-example image.
  ///
  /// In en, this message translates to:
  /// **'Good example'**
  String get avatarGuideExampleGood;

  /// Button to retake/replace the try-on photo.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get avatarRetake;

  /// Shown while the on-device pose check runs.
  ///
  /// In en, this message translates to:
  /// **'Checking your photo…'**
  String get avatarChecking;

  /// Shown when the photo passes validation.
  ///
  /// In en, this message translates to:
  /// **'Looks great — full body detected.'**
  String get avatarCheckOk;

  /// Pose validation: no person detected.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find a person. Use a clear full-body photo.'**
  String get avatarCheckNoPerson;

  /// Pose validation: head not visible.
  ///
  /// In en, this message translates to:
  /// **'Your head isn\'t fully in frame. Include head to feet.'**
  String get avatarCheckHead;

  /// Pose validation: feet not visible.
  ///
  /// In en, this message translates to:
  /// **'Your feet aren\'t visible. Step back so the whole body shows.'**
  String get avatarCheckFeet;

  /// Generic pose-validation failure / error.
  ///
  /// In en, this message translates to:
  /// **'That photo won\'t work for try-on. Please try another.'**
  String get avatarCheckFailGeneric;

  /// Label for the gender selector.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get avatarGenderLabel;

  /// Gender option.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get avatarGenderFemale;

  /// Gender option.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get avatarGenderMale;

  /// Gender option.
  ///
  /// In en, this message translates to:
  /// **'Non-binary'**
  String get avatarGenderNonBinary;

  /// Gender option.
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get avatarGenderPreferNot;

  /// Centimetres unit toggle.
  ///
  /// In en, this message translates to:
  /// **'cm'**
  String get avatarHeightUnitCm;

  /// Feet/inches unit toggle.
  ///
  /// In en, this message translates to:
  /// **'ft/in'**
  String get avatarHeightUnitFt;

  /// Feet field suffix.
  ///
  /// In en, this message translates to:
  /// **'ft'**
  String get avatarHeightFeet;

  /// Inches field suffix.
  ///
  /// In en, this message translates to:
  /// **'in'**
  String get avatarHeightInches;

  /// Body type.
  ///
  /// In en, this message translates to:
  /// **'Petite'**
  String get avatarBodyPetite;

  /// Body type.
  ///
  /// In en, this message translates to:
  /// **'Tall'**
  String get avatarBodyTall;

  /// Body type (feminine shapes).
  ///
  /// In en, this message translates to:
  /// **'Hourglass'**
  String get avatarBodyHourglass;

  /// Body type (feminine shapes).
  ///
  /// In en, this message translates to:
  /// **'Pear'**
  String get avatarBodyPear;

  /// Body type (feminine shapes).
  ///
  /// In en, this message translates to:
  /// **'Apple'**
  String get avatarBodyApple;

  /// Body type.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get avatarBodyRectangle;

  /// Body type (masculine shapes).
  ///
  /// In en, this message translates to:
  /// **'Muscular'**
  String get avatarBodyMuscular;

  /// Body type (masculine shapes).
  ///
  /// In en, this message translates to:
  /// **'Broad'**
  String get avatarBodyBroad;

  /// Body type (masculine shapes).
  ///
  /// In en, this message translates to:
  /// **'Lean'**
  String get avatarBodyLean;

  /// Body type (masculine shapes).
  ///
  /// In en, this message translates to:
  /// **'Stocky'**
  String get avatarBodyStocky;

  /// Label for the fit-preference chips.
  ///
  /// In en, this message translates to:
  /// **'Fit preference'**
  String get avatarFitLabel;

  /// Fit preference.
  ///
  /// In en, this message translates to:
  /// **'Slim'**
  String get avatarFitSlim;

  /// Fit preference.
  ///
  /// In en, this message translates to:
  /// **'Regular'**
  String get avatarFitRegular;

  /// Fit preference.
  ///
  /// In en, this message translates to:
  /// **'Relaxed'**
  String get avatarFitRelaxed;

  /// Note above the optional body fields.
  ///
  /// In en, this message translates to:
  /// **'Optional — improves fit and styling suggestions.'**
  String get avatarOptionalNote;

  /// Optional weight field label.
  ///
  /// In en, this message translates to:
  /// **'Weight (kg)'**
  String get avatarWeightLabel;

  /// Optional age-range label.
  ///
  /// In en, this message translates to:
  /// **'Age range'**
  String get avatarAgeLabel;

  /// Age range option.
  ///
  /// In en, this message translates to:
  /// **'Under 18'**
  String get avatarAgeUnder18;

  /// Age range option.
  ///
  /// In en, this message translates to:
  /// **'18–24'**
  String get avatarAge1824;

  /// Age range option.
  ///
  /// In en, this message translates to:
  /// **'25–34'**
  String get avatarAge2534;

  /// Age range option.
  ///
  /// In en, this message translates to:
  /// **'35–44'**
  String get avatarAge3544;

  /// Age range option.
  ///
  /// In en, this message translates to:
  /// **'45–54'**
  String get avatarAge4554;

  /// Age range option.
  ///
  /// In en, this message translates to:
  /// **'55+'**
  String get avatarAge55Plus;

  /// Optional skin-tone label (stylist color matching).
  ///
  /// In en, this message translates to:
  /// **'Skin tone'**
  String get avatarSkinToneLabel;

  /// Skin tone.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get avatarSkinFair;

  /// Skin tone.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get avatarSkinLight;

  /// Skin tone.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get avatarSkinMedium;

  /// Skin tone.
  ///
  /// In en, this message translates to:
  /// **'Olive'**
  String get avatarSkinOlive;

  /// Skin tone.
  ///
  /// In en, this message translates to:
  /// **'Brown'**
  String get avatarSkinBrown;

  /// Skin tone.
  ///
  /// In en, this message translates to:
  /// **'Deep'**
  String get avatarSkinDeep;

  /// Label for the decorative display picture.
  ///
  /// In en, this message translates to:
  /// **'Profile picture'**
  String get profilePictureLabel;

  /// Explains the profile picture is not the try-on photo.
  ///
  /// In en, this message translates to:
  /// **'Any photo you like — this is separate from your try-on photo.'**
  String get profilePictureHint;

  /// Snackbar after updating the display picture.
  ///
  /// In en, this message translates to:
  /// **'Profile picture updated'**
  String get profilePictureSaved;

  /// Snackbar when the display picture update fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update your picture. Please try again.'**
  String get profilePictureError;

  /// Remove the display picture.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get profilePictureRemove;

  /// Snackbar after removing the display picture.
  ///
  /// In en, this message translates to:
  /// **'Profile picture removed'**
  String get profilePictureRemoved;

  /// Generic done/finish action.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// Profile tile opening the account details screen.
  ///
  /// In en, this message translates to:
  /// **'Personal details'**
  String get profilePersonalDetails;

  /// Account details screen title.
  ///
  /// In en, this message translates to:
  /// **'Personal details'**
  String get accountDetailsTitle;

  /// Section header for editable profile fields.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get accountSectionProfile;

  /// Section header for email/password.
  ///
  /// In en, this message translates to:
  /// **'Sign-in & security'**
  String get accountSectionSecurity;

  /// Display name field.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get accountNameLabel;

  /// Phone field.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get accountPhoneLabel;

  /// Save profile fields.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get accountSave;

  /// Snackbar after saving profile fields.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get accountSaved;

  /// Snackbar when saving profile fields fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save. Please try again.'**
  String get accountSaveError;

  /// Change-email field.
  ///
  /// In en, this message translates to:
  /// **'New email'**
  String get accountEmailLabel;

  /// Shows the current account email.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {email}'**
  String accountEmailCurrent(String email);

  /// Submit an email change.
  ///
  /// In en, this message translates to:
  /// **'Change email'**
  String get accountChangeEmail;

  /// Explains email change requires confirmation.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send a confirmation link to the new address; the change applies once you confirm.'**
  String get accountEmailNote;

  /// Snackbar after requesting an email change.
  ///
  /// In en, this message translates to:
  /// **'Check your new email to confirm the change.'**
  String get accountEmailChanged;

  /// New-password field.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get accountPasswordLabel;

  /// Submit a password change.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get accountChangePassword;

  /// Snackbar after changing password.
  ///
  /// In en, this message translates to:
  /// **'Password updated.'**
  String get accountPasswordChanged;

  /// Password validation message.
  ///
  /// In en, this message translates to:
  /// **'Use at least 8 characters.'**
  String get accountPasswordTooShort;

  /// Current-password field (verified before a password change).
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get accountCurrentPasswordLabel;

  /// Shown when re-authentication fails on password change.
  ///
  /// In en, this message translates to:
  /// **'Current password is incorrect.'**
  String get accountCurrentPasswordWrong;

  /// Snackbar when an email/password change fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update. Please sign in again and retry.'**
  String get accountAuthError;

  /// Link on the sign-in screen to start a password reset.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPassword;

  /// Forgot-password dialog title.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get authForgotTitle;

  /// Forgot-password dialog body.
  ///
  /// In en, this message translates to:
  /// **'Enter your email and we\'ll send a reset link.'**
  String get authForgotBody;

  /// Send the reset email.
  ///
  /// In en, this message translates to:
  /// **'Send link'**
  String get authForgotSend;

  /// Snackbar after sending the reset email.
  ///
  /// In en, this message translates to:
  /// **'Check your email for a reset link.'**
  String get authForgotSent;

  /// Recovery set-new-password screen title.
  ///
  /// In en, this message translates to:
  /// **'Set a new password'**
  String get setPasswordTitle;

  /// Confirm the new password.
  ///
  /// In en, this message translates to:
  /// **'Update password'**
  String get setPasswordCta;

  /// Add a new try-on photo to the gallery.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get avatarGalleryAdd;

  /// Hint above the try-on photo gallery.
  ///
  /// In en, this message translates to:
  /// **'Tap a photo to use it for try-on. Add a few and keep your best.'**
  String get avatarGalleryHint;

  /// Empty state for the try-on gallery.
  ///
  /// In en, this message translates to:
  /// **'Add a full-body photo to try clothes on yourself.'**
  String get avatarGalleryEmpty;

  /// Per-photo quality score badge.
  ///
  /// In en, this message translates to:
  /// **'Quality {score}'**
  String avatarQualityBadge(int score);

  /// Badge on the selected try-on photo.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get avatarSelectedBadge;

  /// Delete-photo confirm title.
  ///
  /// In en, this message translates to:
  /// **'Remove photo?'**
  String get avatarPhotoDeleteTitle;

  /// Delete-photo confirm body.
  ///
  /// In en, this message translates to:
  /// **'This try-on photo will be deleted.'**
  String get avatarPhotoDeleteBody;

  /// Snackbar after deleting a try-on photo.
  ///
  /// In en, this message translates to:
  /// **'Photo removed'**
  String get avatarPhotoDeleted;

  /// Snackbar when deleting a try-on photo fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t remove. Please try again.'**
  String get avatarPhotoDeleteError;

  /// Snackbar when an external link fails to open.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link.'**
  String get profileLinkError;

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

  /// Shown on the paywall when the user already has an active subscription.
  ///
  /// In en, this message translates to:
  /// **'You\'re Premium'**
  String get paywallActiveTitle;

  /// Body shown when the user is already subscribed.
  ///
  /// In en, this message translates to:
  /// **'You have full access to Fashion OS. Manage your plan in the app store.'**
  String get paywallActiveBody;

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
