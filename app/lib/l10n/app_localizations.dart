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
  /// **'Wear The Mood'**
  String get appTitle;

  /// Product tagline / subtitle shown on the splash and onboarding.
  ///
  /// In en, this message translates to:
  /// **'Your personal Fashion OS'**
  String get appTagline;

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
  /// **'You\'ve used all your free AI try-ons.'**
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

  /// No description provided for @addPieceHowTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose how to add this piece'**
  String get addPieceHowTitle;

  /// No description provided for @addPieceRemoveBgTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove background'**
  String get addPieceRemoveBgTitle;

  /// No description provided for @addPieceRemoveBgSub.
  ///
  /// In en, this message translates to:
  /// **'Free · quick closet item'**
  String get addPieceRemoveBgSub;

  /// No description provided for @addPieceEnhanceTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Enhance'**
  String get addPieceEnhanceTitle;

  /// No description provided for @addPieceEnhanceSub.
  ///
  /// In en, this message translates to:
  /// **'Pro / Pro Max · credits used'**
  String get addPieceEnhanceSub;

  /// No description provided for @addPieceEnhanceDesc.
  ///
  /// In en, this message translates to:
  /// **'Make it clean, sharp and catalog-ready.'**
  String get addPieceEnhanceDesc;

  /// Add-a-piece CTA when AI Enhance is selected.
  ///
  /// In en, this message translates to:
  /// **'Enhance & add · {credits, plural, =1{1 credit} other{{credits} credits}}'**
  String addPieceEnhanceCta(int credits);

  /// No description provided for @addPieceEnhanceLocked.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro or Pro Max to use AI Enhance.'**
  String get addPieceEnhanceLocked;

  /// No description provided for @addPieceEnhanceStarted.
  ///
  /// In en, this message translates to:
  /// **'Added — enhancing your piece…'**
  String get addPieceEnhanceStarted;

  /// No description provided for @wardrobeEnhancingBadge.
  ///
  /// In en, this message translates to:
  /// **'Enhancing…'**
  String get wardrobeEnhancingBadge;

  /// No description provided for @wardrobeEnhanceItem.
  ///
  /// In en, this message translates to:
  /// **'Enhance item'**
  String get wardrobeEnhanceItem;

  /// No description provided for @wardrobeEnhanceStarted.
  ///
  /// In en, this message translates to:
  /// **'Enhancing your piece…'**
  String get wardrobeEnhanceStarted;

  /// No description provided for @wardrobeEnhanceError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start enhancing. Please try again.'**
  String get wardrobeEnhanceError;

  /// No description provided for @aiUploadDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Only upload photos you own or have permission to use. AI results may not perfectly match fabric, color, logo, or fit.'**
  String get aiUploadDisclaimer;

  /// Credit-confirmation body before an AI generation.
  ///
  /// In en, this message translates to:
  /// **'This will use {credits, plural, =1{1 credit} other{{credits} credits}}. AI results may slightly change fabric, color, logo, or texture.'**
  String aiCreditConfirm(int credits);

  /// No description provided for @closetShowOnModel.
  ///
  /// In en, this message translates to:
  /// **'Show on model'**
  String get closetShowOnModel;

  /// No description provided for @catalogTitle.
  ///
  /// In en, this message translates to:
  /// **'Catalog Model Shot'**
  String get catalogTitle;

  /// No description provided for @catalogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See this piece on an AI fashion model.'**
  String get catalogSubtitle;

  /// No description provided for @catalogStyleLabel.
  ///
  /// In en, this message translates to:
  /// **'Model style'**
  String get catalogStyleLabel;

  /// No description provided for @catalogStyleStudio.
  ///
  /// In en, this message translates to:
  /// **'Studio'**
  String get catalogStyleStudio;

  /// No description provided for @catalogStyleStreetwear.
  ///
  /// In en, this message translates to:
  /// **'Streetwear'**
  String get catalogStyleStreetwear;

  /// No description provided for @catalogStyleModest.
  ///
  /// In en, this message translates to:
  /// **'Modest'**
  String get catalogStyleModest;

  /// No description provided for @catalogStyleLuxury.
  ///
  /// In en, this message translates to:
  /// **'Luxury'**
  String get catalogStyleLuxury;

  /// No description provided for @catalogStyleCropped.
  ///
  /// In en, this message translates to:
  /// **'Cropped face'**
  String get catalogStyleCropped;

  /// No description provided for @catalogQualityLabel.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get catalogQualityLabel;

  /// No description provided for @catalogQualityStandard.
  ///
  /// In en, this message translates to:
  /// **'Pro Standard'**
  String get catalogQualityStandard;

  /// No description provided for @catalogQualityHd.
  ///
  /// In en, this message translates to:
  /// **'Pro Max HD'**
  String get catalogQualityHd;

  /// Catalog model shot generate button with credit cost.
  ///
  /// In en, this message translates to:
  /// **'Generate · {credits, plural, =1{1 credit} other{{credits} credits}}'**
  String catalogGenerateCta(int credits);

  /// No description provided for @catalogProTitle.
  ///
  /// In en, this message translates to:
  /// **'Catalog shots are a Pro feature'**
  String get catalogProTitle;

  /// No description provided for @catalogProBody.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro or Pro Max to put your pieces on AI fashion models.'**
  String get catalogProBody;

  /// No description provided for @catalogGenerating.
  ///
  /// In en, this message translates to:
  /// **'Creating your model shot…'**
  String get catalogGenerating;

  /// No description provided for @catalogResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Your model shot'**
  String get catalogResultTitle;

  /// No description provided for @catalogSavedNote.
  ///
  /// In en, this message translates to:
  /// **'Saved to your AI Looks.'**
  String get catalogSavedNote;

  /// No description provided for @catalogError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create that. Your credit was refunded.'**
  String get catalogError;

  /// No description provided for @aiLooksTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Looks'**
  String get aiLooksTitle;

  /// No description provided for @aiLooksEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your AI-generated looks will appear here.'**
  String get aiLooksEmpty;

  /// No description provided for @aiLooksReport.
  ///
  /// In en, this message translates to:
  /// **'Report image'**
  String get aiLooksReport;

  /// No description provided for @aiLooksDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get aiLooksDelete;

  /// No description provided for @aiLooksSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get aiLooksSave;

  /// No description provided for @aiLooksShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get aiLooksShare;

  /// No description provided for @aiLooksDeleted.
  ///
  /// In en, this message translates to:
  /// **'Removed from AI Looks'**
  String get aiLooksDeleted;

  /// No description provided for @aiLooksReported.
  ///
  /// In en, this message translates to:
  /// **'Reported. Thanks for flagging.'**
  String get aiLooksReported;

  /// No description provided for @aiLooksError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your AI Looks.'**
  String get aiLooksError;

  /// No description provided for @aiStudioTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Studio'**
  String get aiStudioTitle;

  /// No description provided for @aiStudioSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enhance pieces, create model shots, and try looks on studio models.'**
  String get aiStudioSubtitle;

  /// No description provided for @aiStudioOpen.
  ///
  /// In en, this message translates to:
  /// **'Open Studio'**
  String get aiStudioOpen;

  /// No description provided for @aiStudioEnhance.
  ///
  /// In en, this message translates to:
  /// **'Enhance an item'**
  String get aiStudioEnhance;

  /// No description provided for @aiStudioEnhanceSub.
  ///
  /// In en, this message translates to:
  /// **'Make a piece clean and catalog-ready'**
  String get aiStudioEnhanceSub;

  /// No description provided for @aiStudioCatalog.
  ///
  /// In en, this message translates to:
  /// **'Create model shot'**
  String get aiStudioCatalog;

  /// No description provided for @aiStudioCatalogSub.
  ///
  /// In en, this message translates to:
  /// **'Show a piece on an AI model'**
  String get aiStudioCatalogSub;

  /// No description provided for @aiStudioTryStudio.
  ///
  /// In en, this message translates to:
  /// **'Try on studio model'**
  String get aiStudioTryStudio;

  /// No description provided for @aiStudioTryStudioSub.
  ///
  /// In en, this message translates to:
  /// **'See looks on a studio model'**
  String get aiStudioTryStudioSub;

  /// No description provided for @aiStudioViewLooks.
  ///
  /// In en, this message translates to:
  /// **'View AI Looks'**
  String get aiStudioViewLooks;

  /// No description provided for @aiStudioViewLooksSub.
  ///
  /// In en, this message translates to:
  /// **'Your saved AI-generated images'**
  String get aiStudioViewLooksSub;

  /// No description provided for @aiStudioMyModel.
  ///
  /// In en, this message translates to:
  /// **'My Style Model'**
  String get aiStudioMyModel;

  /// No description provided for @aiStudioMyModelSub.
  ///
  /// In en, this message translates to:
  /// **'Create a reusable model inspired by your look.'**
  String get aiStudioMyModelSub;

  /// No description provided for @aiStudioComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get aiStudioComingSoon;

  /// No description provided for @tierFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get tierFree;

  /// No description provided for @tierPro.
  ///
  /// In en, this message translates to:
  /// **'Pro'**
  String get tierPro;

  /// No description provided for @tierProMax.
  ///
  /// In en, this message translates to:
  /// **'Pro Max'**
  String get tierProMax;

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

  /// Recoverable overlay on a wardrobe tile when its cutout is taking unusually long; tapping re-queries.
  ///
  /// In en, this message translates to:
  /// **'Still working — tap to refresh'**
  String get wardrobeStillWorking;

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

  /// Tooltip for the leaderboard scoring-info button.
  ///
  /// In en, this message translates to:
  /// **'How points work'**
  String get leaderboardHowTooltip;

  /// Title of the leaderboard scoring explainer.
  ///
  /// In en, this message translates to:
  /// **'How points work'**
  String get leaderboardHowTitle;

  /// Intro line of the scoring explainer.
  ///
  /// In en, this message translates to:
  /// **'Climb the monthly Style Score by sharing looks the community loves.'**
  String get leaderboardHowIntro;

  /// Scoring action: posting a look.
  ///
  /// In en, this message translates to:
  /// **'Post a look'**
  String get leaderboardHowPost;

  /// Scoring action: a like received on your look.
  ///
  /// In en, this message translates to:
  /// **'Each like your look gets'**
  String get leaderboardHowLike;

  /// Scoring action: a comment received on your look.
  ///
  /// In en, this message translates to:
  /// **'Each comment your look gets'**
  String get leaderboardHowComment;

  /// Points pill in the scoring explainer.
  ///
  /// In en, this message translates to:
  /// **'+{points}'**
  String leaderboardHowPoints(int points);

  /// Scoring rule: self-engagement is excluded.
  ///
  /// In en, this message translates to:
  /// **'Only other people\'s likes and comments count — you can\'t boost your own.'**
  String get leaderboardHowNoSelf;

  /// Scoring rule: monthly window, live updates, ties.
  ///
  /// In en, this message translates to:
  /// **'Scores cover this calendar month and reset on the 1st. Standings update live; ties share a rank.'**
  String get leaderboardHowMonthly;

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

  /// Overflow action to edit the user's own post.
  ///
  /// In en, this message translates to:
  /// **'Edit post'**
  String get postEdit;

  /// Subtle label shown on a post that was edited.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get postEditedLabel;

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

  /// App-bar title of the composer in edit mode.
  ///
  /// In en, this message translates to:
  /// **'Edit post'**
  String get composeEditTitle;

  /// Button that saves edits to an existing post.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get composeSaveChanges;

  /// Snackbar confirming a post edit was saved.
  ///
  /// In en, this message translates to:
  /// **'Post updated'**
  String get composeEditSaved;

  /// Toggle in the composer to attach a poll.
  ///
  /// In en, this message translates to:
  /// **'Add a poll'**
  String get composeAddPoll;

  /// Inline hint when a poll is enabled but not yet valid, explaining why Share is disabled.
  ///
  /// In en, this message translates to:
  /// **'Add a question and at least 2 options to share your poll.'**
  String get composePollIncomplete;

  /// Label for the poll question field.
  ///
  /// In en, this message translates to:
  /// **'Poll question'**
  String get composePollQuestion;

  /// Hint for the poll question field.
  ///
  /// In en, this message translates to:
  /// **'Ask the community something'**
  String get composePollQuestionHint;

  /// Label for a poll option field.
  ///
  /// In en, this message translates to:
  /// **'Option {number}'**
  String composePollOption(int number);

  /// Button to add another poll option (max 4).
  ///
  /// In en, this message translates to:
  /// **'Add option'**
  String get composePollAddOption;

  /// Label shown on a closed poll.
  ///
  /// In en, this message translates to:
  /// **'Poll closed'**
  String get pollClosed;

  /// Total votes under a poll.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No votes yet} =1{1 vote} other{{count} votes}}'**
  String pollTotalVotes(int count);

  /// Snackbar when casting a poll vote fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t record your vote. Please try again.'**
  String get pollVoteError;

  /// Home section header for the Style Quiz.
  ///
  /// In en, this message translates to:
  /// **'Discover your Style DNA'**
  String get quizHomeTitle;

  /// Title on the Home quiz entry card.
  ///
  /// In en, this message translates to:
  /// **'What\'s your Style DNA?'**
  String get quizHomeCardTitle;

  /// Body on the Home quiz entry card.
  ///
  /// In en, this message translates to:
  /// **'Take a 1-minute quiz to reveal your style.'**
  String get quizHomeCardBody;

  /// Button to start the Style Quiz.
  ///
  /// In en, this message translates to:
  /// **'Take the quiz'**
  String get quizStart;

  /// Quiz progress indicator (question current of total).
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String quizProgress(int current, int total);

  /// Heading on the quiz result screen.
  ///
  /// In en, this message translates to:
  /// **'Your Style DNA'**
  String get quizResultTitle;

  /// Button to share the Style DNA result as a post.
  ///
  /// In en, this message translates to:
  /// **'Share to Community'**
  String get quizShare;

  /// Button to save/keep the Style DNA result.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get quizSave;

  /// Snackbar confirming the result was saved.
  ///
  /// In en, this message translates to:
  /// **'Saved to your profile'**
  String get quizSaved;

  /// Button to retake the Style Quiz.
  ///
  /// In en, this message translates to:
  /// **'Retake quiz'**
  String get quizRetake;

  /// Error state on the quiz screen.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the quiz. Please try again.'**
  String get quizError;

  /// Snackbar when submitting the quiz fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t compute your result. Please try again.'**
  String get quizSubmitError;

  /// Profile prompt when no quiz result yet.
  ///
  /// In en, this message translates to:
  /// **'Take the Style Quiz to reveal your Style DNA.'**
  String get quizProfileEmpty;

  /// Community tab label for giveaways.
  ///
  /// In en, this message translates to:
  /// **'Giveaway'**
  String get communityTabGiveaway;

  /// Community tab label for the affiliate offers section.
  ///
  /// In en, this message translates to:
  /// **'Offers'**
  String get communityTabOffers;

  /// Empty state title for the giveaway grid.
  ///
  /// In en, this message translates to:
  /// **'No giveaways yet'**
  String get giveawayEmptyTitle;

  /// Empty state message for the giveaway grid.
  ///
  /// In en, this message translates to:
  /// **'Free pieces shared by the community will show up here.'**
  String get giveawayEmptyMessage;

  /// Button to create a giveaway listing.
  ///
  /// In en, this message translates to:
  /// **'List an item'**
  String get giveawayList;

  /// Link to the user's own giveaway listings + claims.
  ///
  /// In en, this message translates to:
  /// **'My giveaways'**
  String get giveawayMine;

  /// Warm header tagline at the top of the Giveaway section.
  ///
  /// In en, this message translates to:
  /// **'Sharing is caring — give your loved clothes a second home.'**
  String get giveawayPromoTitle;

  /// Supporting subline under the Giveaway promo tagline.
  ///
  /// In en, this message translates to:
  /// **'One person\'s closet clear-out is another\'s favourite find. Pass it on, for free.'**
  String get giveawayPromoSubtitle;

  /// Empty state for the user's giveaways.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t listed anything yet.'**
  String get giveawayMineEmpty;

  /// Title of the create-giveaway screen.
  ///
  /// In en, this message translates to:
  /// **'Give it away'**
  String get giveawayCreateTitle;

  /// Label for the giveaway title field.
  ///
  /// In en, this message translates to:
  /// **'What are you giving away?'**
  String get giveawayFieldTitle;

  /// Label for the giveaway description field.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get giveawayFieldDescription;

  /// Label for the size field.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get giveawayFieldSize;

  /// Label for the category field.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get giveawayFieldCategory;

  /// Label for the condition field.
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get giveawayFieldCondition;

  /// Label for the coarse area field.
  ///
  /// In en, this message translates to:
  /// **'Area (e.g. neighbourhood)'**
  String get giveawayFieldArea;

  /// Button to add a giveaway photo.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get giveawayAddPhoto;

  /// Button to publish the giveaway.
  ///
  /// In en, this message translates to:
  /// **'Publish listing'**
  String get giveawayPublish;

  /// Snackbar after publishing a giveaway.
  ///
  /// In en, this message translates to:
  /// **'Your giveaway is live'**
  String get giveawayPublished;

  /// Snackbar when publishing fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t publish that. Please try again.'**
  String get giveawayPublishError;

  /// Safety disclaimer shown on create + claim (§10).
  ///
  /// In en, this message translates to:
  /// **'Exchanges are between members — Fashion OS isn\'t a party to them. Keep chat in-app, never share your address or phone in a listing, and meet in a safe public place.'**
  String get giveawayDisclaimer;

  /// Button to claim a giveaway.
  ///
  /// In en, this message translates to:
  /// **'I want this'**
  String get giveawayClaim;

  /// Label for the claim message field.
  ///
  /// In en, this message translates to:
  /// **'Message to the owner (optional)'**
  String get giveawayClaimMessage;

  /// Button to send a claim request.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get giveawayClaimSend;

  /// Snackbar after claiming.
  ///
  /// In en, this message translates to:
  /// **'Request sent'**
  String get giveawayClaimed;

  /// Snackbar when a claim fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send that. Please try again.'**
  String get giveawayClaimError;

  /// Header for the owner's claims inbox.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get giveawayClaimsTitle;

  /// Empty state for the claims inbox.
  ///
  /// In en, this message translates to:
  /// **'No requests yet.'**
  String get giveawayNoClaims;

  /// Accept a claim.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get giveawayAccept;

  /// Decline a claim.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get giveawayDecline;

  /// Owner closes the listing.
  ///
  /// In en, this message translates to:
  /// **'Close listing'**
  String get giveawayClose;

  /// Report a giveaway listing (§19).
  ///
  /// In en, this message translates to:
  /// **'Report listing'**
  String get giveawayReport;

  /// Caption when sharing a giveaway to other apps.
  ///
  /// In en, this message translates to:
  /// **'Check out this giveaway on Wear The Mood — free fashion finds from the style community.'**
  String get giveawayShareText;

  /// Shown when the viewer has a pending claim.
  ///
  /// In en, this message translates to:
  /// **'Request sent — waiting for the owner.'**
  String get giveawayClaimPending;

  /// Shown when the viewer's claim was accepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted! Arrange pickup with the owner in-app.'**
  String get giveawayClaimAcceptedNote;

  /// Generic giveaway error.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this. Please try again.'**
  String get giveawayError;

  /// Request count on a giveaway card.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Free · be the first} =1{1 request} other{{count} requests}}'**
  String giveawayRequestsCount(int count);

  /// Newsroom section header for affiliate offers.
  ///
  /// In en, this message translates to:
  /// **'Offers'**
  String get offersStripTitle;

  /// Subtitle clarifying offers are affiliate deals.
  ///
  /// In en, this message translates to:
  /// **'Curated deals — affiliate links'**
  String get offersStripSubtitle;

  /// Error state title for the Offers section.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load offers'**
  String get offersErrorTitle;

  /// Empty state title for the Offers section.
  ///
  /// In en, this message translates to:
  /// **'No offers right now'**
  String get offersEmptyTitle;

  /// Empty state message for the Offers section.
  ///
  /// In en, this message translates to:
  /// **'Check back soon for fresh deals.'**
  String get offersEmptyMessage;

  /// Affiliate call-to-action on an offer card.
  ///
  /// In en, this message translates to:
  /// **'Shop deal'**
  String get offersShopNow;

  /// Home section header for the daily guide.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get guideTodayTitle;

  /// Button to open the full daily guide.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get guideRead;

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

  /// Validation message when a caption contains an email address (§10).
  ///
  /// In en, this message translates to:
  /// **'Please don\'t include email addresses in public posts.'**
  String get composeCaptionEmail;

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
  /// **'Join me on Wear The Mood — try clothes on before you buy. Use my code {code} when you sign up and we both get free try-ons!'**
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
  /// **'Try any look on yourself with MoodMirror before you buy.'**
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
  /// **'Wear The Mood uses your photos and body details only to create your avatar and try-ons. Raw inputs are deleted after processing — never sold.'**
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

  /// Sign-in failed: wrong email/password or no such user.
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password. Please try again.'**
  String get authErrorInvalidCredentials;

  /// Sign-in blocked because the email isn't confirmed yet.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your email first — check your inbox for the link.'**
  String get authErrorEmailNotConfirmed;

  /// Sign-up failed: the email already has an account.
  ///
  /// In en, this message translates to:
  /// **'That email is already registered. Try signing in instead.'**
  String get authErrorEmailRegistered;

  /// Sign-up failed: password too weak.
  ///
  /// In en, this message translates to:
  /// **'Choose a stronger password (at least 8 characters).'**
  String get authErrorWeakPassword;

  /// Auth blocked by rate limiting.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a moment and try again.'**
  String get authErrorRateLimited;

  /// Sign-up failed: signups disabled on the server.
  ///
  /// In en, this message translates to:
  /// **'New sign-ups are currently disabled.'**
  String get authErrorSignupDisabled;

  /// Auth failed due to a network/connection problem.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server. Check your connection and try again.'**
  String get authErrorNetwork;

  /// Subtitle on the logged-out welcome gate.
  ///
  /// In en, this message translates to:
  /// **'Sign in to try on looks, build your closet, and get styled every day.'**
  String get welcomeSubtitle;

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

  /// Public bio field on the edit profile screen.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get accountBioLabel;

  /// Bio field placeholder.
  ///
  /// In en, this message translates to:
  /// **'Tell people about your style…'**
  String get accountBioHint;

  /// Style tags field label.
  ///
  /// In en, this message translates to:
  /// **'Style tags'**
  String get accountStyleTagsLabel;

  /// Style tags field placeholder.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated, e.g. modest, minimal'**
  String get accountStyleTagsHint;

  /// Public-profile visibility toggle title.
  ///
  /// In en, this message translates to:
  /// **'Public profile'**
  String get accountPublicTitle;

  /// Explains the public-profile toggle.
  ///
  /// In en, this message translates to:
  /// **'When on, others can open your profile and see your bio, looks and style tags.'**
  String get accountPublicSubtitle;

  /// Badge on own profile when the profile is public.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get profileVisibilityPublic;

  /// Badge on own profile when the profile is private.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get profileVisibilityPrivate;

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
  /// **'Unlimited AI try-ons, your whole closet organized, and HD looks with no watermark — your style OS, fully unlocked.'**
  String get paywallSubtitle;

  /// Paywall feature.
  ///
  /// In en, this message translates to:
  /// **'Unlimited MoodMirror try-ons'**
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
  /// **'You have full access to Wear The Mood. Manage your plan in the app store.'**
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

  /// Honest message shown when RevenueCat isn't configured yet (internal builds).
  ///
  /// In en, this message translates to:
  /// **'Subscriptions aren\'t available yet — AI Try-On already works with your free daily credits, and 2D try-on is always free.'**
  String get paywallSetupRequired;

  /// Internal-build banner noting billing isn't connected yet.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions setup pending'**
  String get paywallSetupBadge;

  /// Bottom-bar note for a store offer without an assumed trial.
  ///
  /// In en, this message translates to:
  /// **'{price} · billed via Google Play. Cancel anytime.'**
  String paywallPriceNote(String price);

  /// Title when no store offerings load.
  ///
  /// In en, this message translates to:
  /// **'Purchases unavailable'**
  String get paywallUnavailableTitle;

  /// Body when no store offerings load.
  ///
  /// In en, this message translates to:
  /// **'Premium isn\'t available to purchase right now. You can still use AI Try-On with your daily credits, and 2D try-on is always free.'**
  String get paywallUnavailableBody;

  /// Clarifies that credits also unlock AI Try-On, not only Premium.
  ///
  /// In en, this message translates to:
  /// **'Your first 3 AI realistic try-ons are free — Premium unlocks unlimited, forever.'**
  String get paywallCreditsNote;

  /// Snackbar when restore finds nothing.
  ///
  /// In en, this message translates to:
  /// **'No previous purchases to restore.'**
  String get paywallRestoreNothing;

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

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get commonShare;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @navCloset.
  ///
  /// In en, this message translates to:
  /// **'Closet'**
  String get navCloset;

  /// No description provided for @navTryOn.
  ///
  /// In en, this message translates to:
  /// **'Try-On'**
  String get navTryOn;

  /// No description provided for @homeStylistReady.
  ///
  /// In en, this message translates to:
  /// **'Your AI stylist is ready'**
  String get homeStylistReady;

  /// No description provided for @homeHelloMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get homeHelloMorning;

  /// No description provided for @homeHelloAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get homeHelloAfternoon;

  /// No description provided for @homeHelloEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get homeHelloEvening;

  /// No description provided for @homeGreetingName.
  ///
  /// In en, this message translates to:
  /// **'{greeting}, {name}'**
  String homeGreetingName(String greeting, String name);

  /// No description provided for @homeHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'MoodMirror'**
  String get homeHeroTitle;

  /// No description provided for @homeHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See clothes on your body before you wear them.'**
  String get homeHeroSubtitle;

  /// No description provided for @homeHeroCta.
  ///
  /// In en, this message translates to:
  /// **'Open MoodMirror'**
  String get homeHeroCta;

  /// No description provided for @homeHeroUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload clothing'**
  String get homeHeroUpload;

  /// No description provided for @homeQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get homeQuickActions;

  /// No description provided for @homeQaTryOnTitle.
  ///
  /// In en, this message translates to:
  /// **'Try on clothes'**
  String get homeQaTryOnTitle;

  /// No description provided for @homeQaTryOnSub.
  ///
  /// In en, this message translates to:
  /// **'See it on you instantly'**
  String get homeQaTryOnSub;

  /// No description provided for @homeQaOutfitTitle.
  ///
  /// In en, this message translates to:
  /// **'Build outfit'**
  String get homeQaOutfitTitle;

  /// No description provided for @homeQaOutfitSub.
  ///
  /// In en, this message translates to:
  /// **'Mix & match your closet'**
  String get homeQaOutfitSub;

  /// No description provided for @homeQaStylistTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s stylist'**
  String get homeQaStylistTitle;

  /// No description provided for @homeQaStylistSub.
  ///
  /// In en, this message translates to:
  /// **'Your daily look'**
  String get homeQaStylistSub;

  /// No description provided for @homeQaPackTitle.
  ///
  /// In en, this message translates to:
  /// **'Pack for a trip'**
  String get homeQaPackTitle;

  /// No description provided for @homeQaPackSub.
  ///
  /// In en, this message translates to:
  /// **'Smart packing list'**
  String get homeQaPackSub;

  /// No description provided for @homeClosetItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items added'**
  String homeClosetItemsCount(int count);

  /// No description provided for @homeBuildClosetTitle.
  ///
  /// In en, this message translates to:
  /// **'Build your digital closet'**
  String get homeBuildClosetTitle;

  /// No description provided for @homeBuildClosetSub.
  ///
  /// In en, this message translates to:
  /// **'Add clothes to unlock styling and try-on.'**
  String get homeBuildClosetSub;

  /// No description provided for @homeAddFirstItem.
  ///
  /// In en, this message translates to:
  /// **'Add first item'**
  String get homeAddFirstItem;

  /// No description provided for @homeSuggestionsTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Suggestions'**
  String get homeSuggestionsTitle;

  /// No description provided for @homeSuggestionStyleTop.
  ///
  /// In en, this message translates to:
  /// **'Style a top with tailored bottoms for a sharp look.'**
  String get homeSuggestionStyleTop;

  /// No description provided for @homeSuggestionAddShoes.
  ///
  /// In en, this message translates to:
  /// **'Add shoes to complete more of your outfits.'**
  String get homeSuggestionAddShoes;

  /// No description provided for @homeSuggestionNeedBottoms.
  ///
  /// In en, this message translates to:
  /// **'Your closet could use a few more bottoms.'**
  String get homeSuggestionNeedBottoms;

  /// No description provided for @homeSuggestionStartCloset.
  ///
  /// In en, this message translates to:
  /// **'Add a few pieces and I\'ll start styling you.'**
  String get homeSuggestionStartCloset;

  /// No description provided for @homeTrendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Trending looks'**
  String get homeTrendingTitle;

  /// No description provided for @homeTrendingSub.
  ///
  /// In en, this message translates to:
  /// **'Fresh from the community'**
  String get homeTrendingSub;

  /// No description provided for @homeTryThisLook.
  ///
  /// In en, this message translates to:
  /// **'Try this look'**
  String get homeTryThisLook;

  /// No description provided for @closetTitle.
  ///
  /// In en, this message translates to:
  /// **'Closet'**
  String get closetTitle;

  /// No description provided for @closetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{items} items · {outfits} outfits'**
  String closetSubtitle(int items, int outfits);

  /// No description provided for @closetSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search your closet'**
  String get closetSearchHint;

  /// No description provided for @closetCatAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get closetCatAll;

  /// No description provided for @closetCatTops.
  ///
  /// In en, this message translates to:
  /// **'Tops'**
  String get closetCatTops;

  /// No description provided for @closetCatBottoms.
  ///
  /// In en, this message translates to:
  /// **'Bottoms'**
  String get closetCatBottoms;

  /// No description provided for @closetCatDresses.
  ///
  /// In en, this message translates to:
  /// **'Dresses'**
  String get closetCatDresses;

  /// No description provided for @closetCatOuterwear.
  ///
  /// In en, this message translates to:
  /// **'Outerwear'**
  String get closetCatOuterwear;

  /// No description provided for @closetCatShoes.
  ///
  /// In en, this message translates to:
  /// **'Shoes'**
  String get closetCatShoes;

  /// No description provided for @closetCatBags.
  ///
  /// In en, this message translates to:
  /// **'Bags'**
  String get closetCatBags;

  /// No description provided for @closetCatAccessories.
  ///
  /// In en, this message translates to:
  /// **'Accessories'**
  String get closetCatAccessories;

  /// No description provided for @closetCatFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get closetCatFavorites;

  /// No description provided for @closetTryOn.
  ///
  /// In en, this message translates to:
  /// **'Try on'**
  String get closetTryOn;

  /// No description provided for @closetStyleIt.
  ///
  /// In en, this message translates to:
  /// **'Style it'**
  String get closetStyleIt;

  /// No description provided for @closetAiOrganize.
  ///
  /// In en, this message translates to:
  /// **'AI organize'**
  String get closetAiOrganize;

  /// No description provided for @closetAiOrganizeSoon.
  ///
  /// In en, this message translates to:
  /// **'AI organize is coming soon.'**
  String get closetAiOrganizeSoon;

  /// No description provided for @closetFavorited.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get closetFavorited;

  /// No description provided for @closetUnfavorited.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get closetUnfavorited;

  /// No description provided for @closetUncategorized.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get closetUncategorized;

  /// No description provided for @closetTapToCategorize.
  ///
  /// In en, this message translates to:
  /// **'Tap to categorize'**
  String get closetTapToCategorize;

  /// No description provided for @closetTabWardrobe.
  ///
  /// In en, this message translates to:
  /// **'Wardrobe'**
  String get closetTabWardrobe;

  /// No description provided for @closetTabAllItems.
  ///
  /// In en, this message translates to:
  /// **'All Items'**
  String get closetTabAllItems;

  /// No description provided for @closetTabOutfits.
  ///
  /// In en, this message translates to:
  /// **'Outfits'**
  String get closetTabOutfits;

  /// No description provided for @wardrobeHangingRail.
  ///
  /// In en, this message translates to:
  /// **'Hanging Rail'**
  String get wardrobeHangingRail;

  /// No description provided for @wardrobeDrawersShelves.
  ///
  /// In en, this message translates to:
  /// **'Drawers & Shelves'**
  String get wardrobeDrawersShelves;

  /// No description provided for @wardrobeFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get wardrobeFavorites;

  /// No description provided for @wardrobeSavedOutfits.
  ///
  /// In en, this message translates to:
  /// **'Saved Outfits'**
  String get wardrobeSavedOutfits;

  /// No description provided for @wardrobeUnsorted.
  ///
  /// In en, this message translates to:
  /// **'Unsorted'**
  String get wardrobeUnsorted;

  /// No description provided for @wardrobeCreateDrawer.
  ///
  /// In en, this message translates to:
  /// **'New drawer'**
  String get wardrobeCreateDrawer;

  /// No description provided for @wardrobeItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Empty} =1{1 item} other{{count} items}}'**
  String wardrobeItemsCount(int count);

  /// No description provided for @drawerDetailSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search this drawer'**
  String get drawerDetailSearchHint;

  /// No description provided for @drawerSortRecent.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get drawerSortRecent;

  /// No description provided for @drawerSortWorn.
  ///
  /// In en, this message translates to:
  /// **'Most worn'**
  String get drawerSortWorn;

  /// No description provided for @drawerSortFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites first'**
  String get drawerSortFavorites;

  /// No description provided for @drawerEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'This drawer is empty'**
  String get drawerEmptyTitle;

  /// No description provided for @drawerEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Add your first item to {name}.'**
  String drawerEmptyMessage(String name);

  /// No description provided for @drawerAddItem.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get drawerAddItem;

  /// No description provided for @drawerStyleThis.
  ///
  /// In en, this message translates to:
  /// **'Style this drawer'**
  String get drawerStyleThis;

  /// No description provided for @drawerStyleThisSoon.
  ///
  /// In en, this message translates to:
  /// **'Outfit ideas for this drawer are coming soon.'**
  String get drawerStyleThisSoon;

  /// No description provided for @drawerRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get drawerRename;

  /// No description provided for @drawerEditAction.
  ///
  /// In en, this message translates to:
  /// **'Edit drawer'**
  String get drawerEditAction;

  /// No description provided for @drawerDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete drawer'**
  String get drawerDeleteAction;

  /// No description provided for @drawerDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this drawer?'**
  String get drawerDeleteConfirmTitle;

  /// No description provided for @drawerDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Your items stay in the closet — only the drawer is removed.'**
  String get drawerDeleteConfirmBody;

  /// No description provided for @drawerDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get drawerDeleteConfirm;

  /// No description provided for @drawerCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New drawer'**
  String get drawerCreateTitle;

  /// No description provided for @drawerEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit drawer'**
  String get drawerEditTitle;

  /// No description provided for @drawerNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Drawer name'**
  String get drawerNameLabel;

  /// No description provided for @drawerNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Summer, Gym, Office'**
  String get drawerNameHint;

  /// No description provided for @drawerIconLabel.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get drawerIconLabel;

  /// No description provided for @drawerColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get drawerColorLabel;

  /// No description provided for @drawerSave.
  ///
  /// In en, this message translates to:
  /// **'Save drawer'**
  String get drawerSave;

  /// No description provided for @drawerNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Give your drawer a name.'**
  String get drawerNameRequired;

  /// No description provided for @drawerMoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to drawer'**
  String get drawerMoveTitle;

  /// No description provided for @drawerAssigned.
  ///
  /// In en, this message translates to:
  /// **'Moved to {name}'**
  String drawerAssigned(String name);

  /// No description provided for @drawerCreated.
  ///
  /// In en, this message translates to:
  /// **'Drawer created'**
  String get drawerCreated;

  /// No description provided for @addItemDrawerLabel.
  ///
  /// In en, this message translates to:
  /// **'Add to drawer'**
  String get addItemDrawerLabel;

  /// No description provided for @addItemDrawerSuggested.
  ///
  /// In en, this message translates to:
  /// **'Suggested'**
  String get addItemDrawerSuggested;

  /// No description provided for @closetMissingPiecesTitle.
  ///
  /// In en, this message translates to:
  /// **'Missing pieces'**
  String get closetMissingPiecesTitle;

  /// No description provided for @closetCleanupTitle.
  ///
  /// In en, this message translates to:
  /// **'Closet clean-up'**
  String get closetCleanupTitle;

  /// No description provided for @closetCleanupBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item needs a category or name} other{{count} items need a category or name}}'**
  String closetCleanupBody(int count);

  /// No description provided for @closetCleanupReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get closetCleanupReview;

  /// No description provided for @closetColorMap.
  ///
  /// In en, this message translates to:
  /// **'Color map'**
  String get closetColorMap;

  /// No description provided for @closetColorMapSoon.
  ///
  /// In en, this message translates to:
  /// **'Color tagging is coming soon.'**
  String get closetColorMapSoon;

  /// No description provided for @profileStatDrawers.
  ///
  /// In en, this message translates to:
  /// **'Drawers'**
  String get profileStatDrawers;

  /// No description provided for @profileSectionPremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get profileSectionPremium;

  /// No description provided for @profileSectionDanger.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get profileSectionDanger;

  /// No description provided for @closetDetailTryOnMe.
  ///
  /// In en, this message translates to:
  /// **'Try on me'**
  String get closetDetailTryOnMe;

  /// No description provided for @closetDetailFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get closetDetailFavorite;

  /// No description provided for @closetDetailUnfavorite.
  ///
  /// In en, this message translates to:
  /// **'Unfavorite'**
  String get closetDetailUnfavorite;

  /// No description provided for @closetDetailPairsTitle.
  ///
  /// In en, this message translates to:
  /// **'Pairs well with'**
  String get closetDetailPairsTitle;

  /// No description provided for @closetDetailPairsValue.
  ///
  /// In en, this message translates to:
  /// **'Neutral bottoms, a light jacket and clean sneakers.'**
  String get closetDetailPairsValue;

  /// No description provided for @closetDetailBestForTitle.
  ///
  /// In en, this message translates to:
  /// **'Best for'**
  String get closetDetailBestForTitle;

  /// No description provided for @closetDetailBestForValue.
  ///
  /// In en, this message translates to:
  /// **'Casual · Workwear · Travel'**
  String get closetDetailBestForValue;

  /// No description provided for @closetDetailRelated.
  ///
  /// In en, this message translates to:
  /// **'More from your closet'**
  String get closetDetailRelated;

  /// No description provided for @tryOnLandingTitle.
  ///
  /// In en, this message translates to:
  /// **'MoodMirror'**
  String get tryOnLandingTitle;

  /// No description provided for @tryOnLandingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Three steps to see any piece on you.'**
  String get tryOnLandingSubtitle;

  /// No description provided for @tryOnBodyTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose try-on body'**
  String get tryOnBodyTitle;

  /// No description provided for @tryOnBodySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Try on your own photo or a studio model.'**
  String get tryOnBodySubtitle;

  /// No description provided for @tryOnBodyMyPhoto.
  ///
  /// In en, this message translates to:
  /// **'My photo'**
  String get tryOnBodyMyPhoto;

  /// No description provided for @tryOnBodyStudioModel.
  ///
  /// In en, this message translates to:
  /// **'Studio model'**
  String get tryOnBodyStudioModel;

  /// No description provided for @tryOnStudioPickHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a studio model to continue.'**
  String get tryOnStudioPickHint;

  /// No description provided for @tryOnStudioComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Studio models are coming soon.'**
  String get tryOnStudioComingSoon;

  /// No description provided for @tryOnStudioComingSoonBody.
  ///
  /// In en, this message translates to:
  /// **'We\'re curating a set of studio models you can try clothes on. Check back soon.'**
  String get tryOnStudioComingSoonBody;

  /// No description provided for @tryOnStudioProTitle.
  ///
  /// In en, this message translates to:
  /// **'Studio models are a Pro feature'**
  String get tryOnStudioProTitle;

  /// No description provided for @tryOnStudioProBody.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro or Pro Max to try clothes on curated studio models.'**
  String get tryOnStudioProBody;

  /// No description provided for @tryOnStudioSelected.
  ///
  /// In en, this message translates to:
  /// **'Studio model selected'**
  String get tryOnStudioSelected;

  /// No description provided for @tryOnStepPhotoTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your photo'**
  String get tryOnStepPhotoTitle;

  /// No description provided for @tryOnStepPhotoSub.
  ///
  /// In en, this message translates to:
  /// **'Use your try-on photo or add a new one.'**
  String get tryOnStepPhotoSub;

  /// No description provided for @tryOnStepClothingTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose clothing'**
  String get tryOnStepClothingTitle;

  /// No description provided for @tryOnStepClothingSub.
  ///
  /// In en, this message translates to:
  /// **'Pick from your closet or upload.'**
  String get tryOnStepClothingSub;

  /// No description provided for @tryOnStepModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick a try-on mode'**
  String get tryOnStepModeTitle;

  /// No description provided for @tryOnStepModeSub.
  ///
  /// In en, this message translates to:
  /// **'2D preview or realistic AI.'**
  String get tryOnStepModeSub;

  /// No description provided for @tryOnStepGenerateTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate your look'**
  String get tryOnStepGenerateTitle;

  /// No description provided for @tryOnStepGenerateSub.
  ///
  /// In en, this message translates to:
  /// **'We render it in seconds.'**
  String get tryOnStepGenerateSub;

  /// No description provided for @tryOnGenerate2d.
  ///
  /// In en, this message translates to:
  /// **'Generate 2D preview'**
  String get tryOnGenerate2d;

  /// No description provided for @tryOnGenerateAi.
  ///
  /// In en, this message translates to:
  /// **'Generate AI look'**
  String get tryOnGenerateAi;

  /// No description provided for @tryOn2dFreeHint.
  ///
  /// In en, this message translates to:
  /// **'Free — no credits used'**
  String get tryOn2dFreeHint;

  /// No description provided for @tryOn2dResultTitle.
  ///
  /// In en, this message translates to:
  /// **'MoodMirror 2D Preview'**
  String get tryOn2dResultTitle;

  /// No description provided for @tryOn2dResultNote.
  ///
  /// In en, this message translates to:
  /// **'On-device preview — adjust anytime.'**
  String get tryOn2dResultNote;

  /// No description provided for @tryOn2dEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust your look'**
  String get tryOn2dEditorTitle;

  /// No description provided for @tryOn2dHint.
  ///
  /// In en, this message translates to:
  /// **'Drag, pinch and rotate to fit'**
  String get tryOn2dHint;

  /// 2D try-on hint shown in canvas (zoom/pan) mode.
  ///
  /// In en, this message translates to:
  /// **'Pinch to zoom · pick a piece to edit'**
  String get tryOn2dHintCanvas;

  /// 2D try-on hint shown while editing a selected piece.
  ///
  /// In en, this message translates to:
  /// **'Drag to place · tap photo to zoom'**
  String get tryOn2dHintEdit;

  /// Tooltip for the reset-zoom (fit to screen) button.
  ///
  /// In en, this message translates to:
  /// **'Fit to screen'**
  String get tryOn2dFit;

  /// No description provided for @tryOn2dDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get tryOn2dDone;

  /// No description provided for @tryOn2dReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get tryOn2dReset;

  /// No description provided for @tryOn2dFlip.
  ///
  /// In en, this message translates to:
  /// **'Flip'**
  String get tryOn2dFlip;

  /// Tool that hides or shows the selected garment layer in the 2D editor.
  ///
  /// In en, this message translates to:
  /// **'Show / hide'**
  String get tryOn2dToggleVisible;

  /// Tool + sheet title for recolouring the selected garment.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get tryOn2dColor;

  /// Colour variant: the garment's original colour.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get tryOn2dColorOriginal;

  /// Colour variant: greyscale.
  ///
  /// In en, this message translates to:
  /// **'Mono'**
  String get tryOn2dColorMono;

  /// Action + sheet title for the composite colour-grade look.
  ///
  /// In en, this message translates to:
  /// **'Look'**
  String get tryOn2dLook;

  /// Look option: no grade.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get tryOn2dLookNone;

  /// Look option: warm grade.
  ///
  /// In en, this message translates to:
  /// **'Warm'**
  String get tryOn2dLookWarm;

  /// Look option: cool grade.
  ///
  /// In en, this message translates to:
  /// **'Cool'**
  String get tryOn2dLookCool;

  /// Toggle to try the look on a stylized mannequin instead of a photo.
  ///
  /// In en, this message translates to:
  /// **'Mannequin'**
  String get tryOn2dMannequin;

  /// Soft upsell chip on the 2D result that leads to the premium AI try-on.
  ///
  /// In en, this message translates to:
  /// **'See it in HD — AI Realistic'**
  String get tryOn2dUpgradeHd;

  /// Title of the 2D editor backdrop picker.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get tryOn2dBackground;

  /// Backdrop option: keep the original photo backdrop.
  ///
  /// In en, this message translates to:
  /// **'Your photo'**
  String get tryOn2dBgPhoto;

  /// Backdrop option: soft studio light.
  ///
  /// In en, this message translates to:
  /// **'Studio'**
  String get tryOn2dBgStudio;

  /// Backdrop option: warm gradient.
  ///
  /// In en, this message translates to:
  /// **'Gradient'**
  String get tryOn2dBgGradient;

  /// Backdrop option: moody editorial.
  ///
  /// In en, this message translates to:
  /// **'Editorial'**
  String get tryOn2dBgEditorial;

  /// No description provided for @tryOn2dSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to your looks'**
  String get tryOn2dSaved;

  /// No description provided for @tryOn2dCaptureError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the preview. Please try again.'**
  String get tryOn2dCaptureError;

  /// No description provided for @tryOnMode2dTitle.
  ///
  /// In en, this message translates to:
  /// **'2D Try-On'**
  String get tryOnMode2dTitle;

  /// No description provided for @tryOnMode2dSub.
  ///
  /// In en, this message translates to:
  /// **'Fast preview · free for everyone'**
  String get tryOnMode2dSub;

  /// No description provided for @tryOnModeAiTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Realistic Try-On'**
  String get tryOnModeAiTitle;

  /// No description provided for @tryOnModeAiSub.
  ///
  /// In en, this message translates to:
  /// **'HD · realistic fabric & body fit'**
  String get tryOnModeAiSub;

  /// No description provided for @tryOnBadgeFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get tryOnBadgeFree;

  /// No description provided for @tryOnBadgePremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get tryOnBadgePremium;

  /// No description provided for @tryOnGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'How to take the perfect photo'**
  String get tryOnGuideTitle;

  /// No description provided for @tryOnGuideFullBody.
  ///
  /// In en, this message translates to:
  /// **'Full body visible, head to feet'**
  String get tryOnGuideFullBody;

  /// No description provided for @tryOnGuidePlainBg.
  ///
  /// In en, this message translates to:
  /// **'Plain, uncluttered background'**
  String get tryOnGuidePlainBg;

  /// No description provided for @tryOnGuideLighting.
  ///
  /// In en, this message translates to:
  /// **'Bright, even lighting'**
  String get tryOnGuideLighting;

  /// No description provided for @tryOnGuideFaceCamera.
  ///
  /// In en, this message translates to:
  /// **'Face the camera'**
  String get tryOnGuideFaceCamera;

  /// No description provided for @tryOnGuideArms.
  ///
  /// In en, this message translates to:
  /// **'Arms slightly away from your body'**
  String get tryOnGuideArms;

  /// No description provided for @tryOnGuideOnePerson.
  ///
  /// In en, this message translates to:
  /// **'Just you — one person only'**
  String get tryOnGuideOnePerson;

  /// No description provided for @tryOnGuideAvoid.
  ///
  /// In en, this message translates to:
  /// **'Avoid close-ups, mirror cutoffs and group photos'**
  String get tryOnGuideAvoid;

  /// No description provided for @tryOnUpgradeTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock AI Realistic Try-On'**
  String get tryOnUpgradeTitle;

  /// No description provided for @tryOnUpgradeBody.
  ///
  /// In en, this message translates to:
  /// **'Go Premium for HD results, realistic fabric and body fit, plus save, share and compare.'**
  String get tryOnUpgradeBody;

  /// No description provided for @tryOnUpgradeCta.
  ///
  /// In en, this message translates to:
  /// **'See Premium'**
  String get tryOnUpgradeCta;

  /// No description provided for @tryOnUpgradeMaybe.
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get tryOnUpgradeMaybe;

  /// No description provided for @tryOnHdToggle.
  ///
  /// In en, this message translates to:
  /// **'Try-On Max (HD)'**
  String get tryOnHdToggle;

  /// No description provided for @tryOnHdToggleSub.
  ///
  /// In en, this message translates to:
  /// **'Sharper render · 4 credits (standard is 1)'**
  String get tryOnHdToggleSub;

  /// No description provided for @tryOnHdLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'HD is a Pro & Pro Max feature'**
  String get tryOnHdLockedTitle;

  /// No description provided for @tryOnHdLockedBody.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro or Pro Max for HD / Try-On Max renders — 4 credits each.'**
  String get tryOnHdLockedBody;

  /// No description provided for @tryOnUpgradeForHd.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro or Pro Max for HD.'**
  String get tryOnUpgradeForHd;

  /// Shown when a subscriber doesn't have enough credits for an HD render.
  ///
  /// In en, this message translates to:
  /// **'You need {count} credits for HD.'**
  String tryOnNeedCreditsHd(int count);

  /// Required-credits helper under the AI generate button.
  ///
  /// In en, this message translates to:
  /// **'Costs {count, plural, =1{1 credit} other{{count} credits}}'**
  String tryOnCostLabel(int count);

  /// Button to buy more credits when a subscriber runs out.
  ///
  /// In en, this message translates to:
  /// **'Top Up'**
  String get tryOnTopUp;

  /// No description provided for @tryOnProgressFitting.
  ///
  /// In en, this message translates to:
  /// **'Fitting the outfit…'**
  String get tryOnProgressFitting;

  /// No description provided for @tryOnProgressMatching.
  ///
  /// In en, this message translates to:
  /// **'Matching body shape…'**
  String get tryOnProgressMatching;

  /// No description provided for @tryOnProgressRendering.
  ///
  /// In en, this message translates to:
  /// **'Rendering your look…'**
  String get tryOnProgressRendering;

  /// No description provided for @tryOnProgressPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing your photo…'**
  String get tryOnProgressPreparing;

  /// No description provided for @tryOnProgressGenerating.
  ///
  /// In en, this message translates to:
  /// **'Generating your look…'**
  String get tryOnProgressGenerating;

  /// No description provided for @tryOnProgressAlmost.
  ///
  /// In en, this message translates to:
  /// **'Almost done…'**
  String get tryOnProgressAlmost;

  /// No description provided for @tryOnProgressLongWait.
  ///
  /// In en, this message translates to:
  /// **'Still working — high-quality looks take a moment.'**
  String get tryOnProgressLongWait;

  /// Subtle elapsed-time counter shown under the try-on progress bar.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String tryOnElapsed(int seconds);

  /// No description provided for @tryOnSaveLook.
  ///
  /// In en, this message translates to:
  /// **'Save look'**
  String get tryOnSaveLook;

  /// No description provided for @tryOnPostCommunity.
  ///
  /// In en, this message translates to:
  /// **'Post to Community'**
  String get tryOnPostCommunity;

  /// No description provided for @tryOnCompare.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get tryOnCompare;

  /// No description provided for @tryOnBefore.
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get tryOnBefore;

  /// No description provided for @tryOnAfter.
  ///
  /// In en, this message translates to:
  /// **'After'**
  String get tryOnAfter;

  /// Confirmation that a try-on look was saved.
  ///
  /// In en, this message translates to:
  /// **'Look saved to your history'**
  String get tryOnLookSaved;

  /// Shown when saving a try-on look fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your look. Please try again.'**
  String get tryOnLookSaveError;

  /// No description provided for @tryOnChangePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change photo'**
  String get tryOnChangePhoto;

  /// No description provided for @tryOnSelectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get tryOnSelectedLabel;

  /// Shown when Try-On is tapped before a piece has any usable image yet.
  ///
  /// In en, this message translates to:
  /// **'Still preparing this piece — try again in a moment.'**
  String get tryOnStillPreparing;

  /// No description provided for @communityCatForYou.
  ///
  /// In en, this message translates to:
  /// **'For You'**
  String get communityCatForYou;

  /// No description provided for @communityCatFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get communityCatFollowing;

  /// No description provided for @communityCatTrending.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get communityCatTrending;

  /// No description provided for @communityCatHijab.
  ///
  /// In en, this message translates to:
  /// **'Hijab Style'**
  String get communityCatHijab;

  /// No description provided for @communityCatCasual.
  ///
  /// In en, this message translates to:
  /// **'Casual'**
  String get communityCatCasual;

  /// No description provided for @communityCatWorkwear.
  ///
  /// In en, this message translates to:
  /// **'Workwear'**
  String get communityCatWorkwear;

  /// No description provided for @communityCatStreetwear.
  ///
  /// In en, this message translates to:
  /// **'Streetwear'**
  String get communityCatStreetwear;

  /// No description provided for @communityCatTravel.
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get communityCatTravel;

  /// No description provided for @communityCatModest.
  ///
  /// In en, this message translates to:
  /// **'Modest'**
  String get communityCatModest;

  /// No description provided for @communityCatMinimal.
  ///
  /// In en, this message translates to:
  /// **'Minimal'**
  String get communityCatMinimal;

  /// No description provided for @communityCatWedding.
  ///
  /// In en, this message translates to:
  /// **'Wedding'**
  String get communityCatWedding;

  /// No description provided for @communityCatOffice.
  ///
  /// In en, this message translates to:
  /// **'Office'**
  String get communityCatOffice;

  /// No description provided for @communityChallengesTitle.
  ///
  /// In en, this message translates to:
  /// **'Style Challenges'**
  String get communityChallengesTitle;

  /// No description provided for @communityChallengesSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get communityChallengesSeeAll;

  /// No description provided for @communityLeaderboardCardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See who\'s topping this month\'s Style Score.'**
  String get communityLeaderboardCardSubtitle;

  /// No description provided for @studioTitle.
  ///
  /// In en, this message translates to:
  /// **'Try-On Studio'**
  String get studioTitle;

  /// No description provided for @studioAddPieces.
  ///
  /// In en, this message translates to:
  /// **'Add pieces'**
  String get studioAddPieces;

  /// No description provided for @studioYourOutfit.
  ///
  /// In en, this message translates to:
  /// **'Your outfit'**
  String get studioYourOutfit;

  /// No description provided for @studioOutfitEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add tops, bottoms, shoes & accessories to build a look.'**
  String get studioOutfitEmpty;

  /// No description provided for @studioRemovePiece.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get studioRemovePiece;

  /// No description provided for @studioLayersTitle.
  ///
  /// In en, this message translates to:
  /// **'Layers'**
  String get studioLayersTitle;

  /// No description provided for @studioBringForward.
  ///
  /// In en, this message translates to:
  /// **'Bring forward'**
  String get studioBringForward;

  /// No description provided for @studioSendBack.
  ///
  /// In en, this message translates to:
  /// **'Send back'**
  String get studioSendBack;

  /// No description provided for @studioDeleteLayer.
  ///
  /// In en, this message translates to:
  /// **'Delete layer'**
  String get studioDeleteLayer;

  /// No description provided for @studioAddItem.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get studioAddItem;

  /// No description provided for @studioSelectLayerHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a piece to move, resize, rotate or fade it'**
  String get studioSelectLayerHint;

  /// No description provided for @studioAiPrimaryNote.
  ///
  /// In en, this message translates to:
  /// **'AI renders your main piece now — full-outfit AI is on the way.'**
  String get studioAiPrimaryNote;

  /// No description provided for @studioAiFullOutfitNote.
  ///
  /// In en, this message translates to:
  /// **'AI renders your full outfit — add your pieces and generate.'**
  String get studioAiFullOutfitNote;

  /// No description provided for @tryOnTooManyGarments.
  ///
  /// In en, this message translates to:
  /// **'You can try on up to {count} pieces at once. Remove a few and try again.'**
  String tryOnTooManyGarments(int count);

  /// No description provided for @studioGenerate2d.
  ///
  /// In en, this message translates to:
  /// **'Build 2D outfit'**
  String get studioGenerate2d;

  /// No description provided for @studioPiecesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No pieces} =1{1 piece} other{{count} pieces}}'**
  String studioPiecesCount(int count);

  /// No description provided for @postSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get postSave;

  /// No description provided for @postSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to your looks'**
  String get postSaved;

  /// No description provided for @postShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get postShare;

  /// No description provided for @postTryThisLook.
  ///
  /// In en, this message translates to:
  /// **'Try this look'**
  String get postTryThisLook;

  /// No description provided for @postTryThisLookEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Choose items from your wardrobe to recreate this look.'**
  String get postTryThisLookEmptyHint;

  /// No description provided for @postShareText.
  ///
  /// In en, this message translates to:
  /// **'Check out this look on Wear The Mood ✨'**
  String get postShareText;

  /// No description provided for @postShareCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard — paste to share.'**
  String get postShareCopied;

  /// No description provided for @shareFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open share. Please try again.'**
  String get shareFailed;

  /// No description provided for @closetWornCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Not worn yet} =1{Worn once} other{Worn {count} times}}'**
  String closetWornCount(int count);

  /// No description provided for @closetLastWorn.
  ///
  /// In en, this message translates to:
  /// **'Last worn {date}'**
  String closetLastWorn(String date);

  /// No description provided for @composeDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard this post?'**
  String get composeDiscardTitle;

  /// No description provided for @composeDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'Your caption and photo will be lost.'**
  String get composeDiscardBody;

  /// No description provided for @composeDiscardConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get composeDiscardConfirm;

  /// No description provided for @composeKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get composeKeepEditing;

  /// No description provided for @profileEditProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get profileEditProfile;

  /// No description provided for @profileTabLooks.
  ///
  /// In en, this message translates to:
  /// **'Looks'**
  String get profileTabLooks;

  /// No description provided for @profileTabSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get profileTabSaved;

  /// No description provided for @profileTabCloset.
  ///
  /// In en, this message translates to:
  /// **'Closet'**
  String get profileTabCloset;

  /// No description provided for @profileTabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get profileTabSettings;

  /// No description provided for @profileStatCloset.
  ///
  /// In en, this message translates to:
  /// **'Closet'**
  String get profileStatCloset;

  /// No description provided for @profileStatOutfits.
  ///
  /// In en, this message translates to:
  /// **'Outfits'**
  String get profileStatOutfits;

  /// No description provided for @profileStatTryOns.
  ///
  /// In en, this message translates to:
  /// **'Try-ons'**
  String get profileStatTryOns;

  /// No description provided for @profileStatSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get profileStatSaved;

  /// No description provided for @profileLooksEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No looks yet'**
  String get profileLooksEmptyTitle;

  /// No description provided for @profileLooksEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Share an outfit and it\'ll show up here.'**
  String get profileLooksEmptyMessage;

  /// No description provided for @profileSavedEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing saved yet'**
  String get profileSavedEmptyTitle;

  /// No description provided for @profileSavedEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Save looks you love from try-on and the community.'**
  String get profileSavedEmptyMessage;

  /// No description provided for @profileClosetEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Your closet preview will appear here.'**
  String get profileClosetEmptyMessage;

  /// No description provided for @profilePremiumBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Fashion OS Premium'**
  String get profilePremiumBannerTitle;

  /// No description provided for @profilePremiumBannerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Realistic AI try-on, unlimited outfits, HD exports and premium styling.'**
  String get profilePremiumBannerSubtitle;

  /// No description provided for @profilePremiumBannerCta.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get profilePremiumBannerCta;

  /// No description provided for @profileStyleTitle.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get profileStyleTitle;

  /// No description provided for @profileBodyPhoto.
  ///
  /// In en, this message translates to:
  /// **'Body & try-on photo'**
  String get profileBodyPhoto;

  /// No description provided for @profileTagCasual.
  ///
  /// In en, this message translates to:
  /// **'Casual'**
  String get profileTagCasual;

  /// No description provided for @profileTagModest.
  ///
  /// In en, this message translates to:
  /// **'Modest'**
  String get profileTagModest;

  /// No description provided for @profileTagStreetwear.
  ///
  /// In en, this message translates to:
  /// **'Streetwear'**
  String get profileTagStreetwear;

  /// No description provided for @profileTagMinimal.
  ///
  /// In en, this message translates to:
  /// **'Minimal'**
  String get profileTagMinimal;

  /// No description provided for @profileTagWorkwear.
  ///
  /// In en, this message translates to:
  /// **'Workwear'**
  String get profileTagWorkwear;

  /// No description provided for @pubProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get pubProfileTitle;

  /// No description provided for @pubProfileFollow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get pubProfileFollow;

  /// No description provided for @pubProfileFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get pubProfileFollowing;

  /// No description provided for @pubProfileMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get pubProfileMessage;

  /// No description provided for @pubProfileMessageSoon.
  ///
  /// In en, this message translates to:
  /// **'Direct messages are coming soon.'**
  String get pubProfileMessageSoon;

  /// No description provided for @pubProfileStatLooks.
  ///
  /// In en, this message translates to:
  /// **'Looks'**
  String get pubProfileStatLooks;

  /// No description provided for @pubProfileStatFollowers.
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get pubProfileStatFollowers;

  /// No description provided for @pubProfileStatFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get pubProfileStatFollowing;

  /// No description provided for @pubProfileTabLooks.
  ///
  /// In en, this message translates to:
  /// **'Looks'**
  String get pubProfileTabLooks;

  /// No description provided for @pubProfileTabCloset.
  ///
  /// In en, this message translates to:
  /// **'Closet'**
  String get pubProfileTabCloset;

  /// No description provided for @pubProfileTabAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get pubProfileTabAbout;

  /// No description provided for @pubProfileLooksEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No looks yet'**
  String get pubProfileLooksEmptyTitle;

  /// No description provided for @pubProfileLooksEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'When {name} shares a look, it\'ll show up here.'**
  String pubProfileLooksEmptyMessage(String name);

  /// No description provided for @pubProfileClosetEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing shared yet'**
  String get pubProfileClosetEmptyTitle;

  /// No description provided for @pubProfileClosetEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'This member hasn\'t shared any closet pieces.'**
  String get pubProfileClosetEmptyMessage;

  /// No description provided for @pubProfileAboutBioEmpty.
  ///
  /// In en, this message translates to:
  /// **'No bio yet.'**
  String get pubProfileAboutBioEmpty;

  /// No description provided for @pubProfileAboutStyleTitle.
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get pubProfileAboutStyleTitle;

  /// No description provided for @pubProfileAboutStyleEmpty.
  ///
  /// In en, this message translates to:
  /// **'No style tags yet.'**
  String get pubProfileAboutStyleEmpty;

  /// No description provided for @pubProfileNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile unavailable'**
  String get pubProfileNotFoundTitle;

  /// No description provided for @pubProfileNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'This profile is private or no longer exists.'**
  String get pubProfileNotFoundMessage;

  /// No description provided for @pubProfileViewProfile.
  ///
  /// In en, this message translates to:
  /// **'View profile'**
  String get pubProfileViewProfile;

  /// No description provided for @pubProfileFollowError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update follow. Please try again.'**
  String get pubProfileFollowError;

  /// No description provided for @followListFollowersTitle.
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get followListFollowersTitle;

  /// No description provided for @followListFollowingTitle.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get followListFollowingTitle;

  /// No description provided for @followListEmptyFollowers.
  ///
  /// In en, this message translates to:
  /// **'No followers yet'**
  String get followListEmptyFollowers;

  /// No description provided for @followListEmptyFollowing.
  ///
  /// In en, this message translates to:
  /// **'Not following anyone yet'**
  String get followListEmptyFollowing;

  /// No description provided for @followListErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load that list'**
  String get followListErrorTitle;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @notificationsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up'**
  String get notificationsEmptyTitle;

  /// No description provided for @notificationsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Likes, comments, follows and try-on updates will show up here.'**
  String get notificationsEmptyMessage;

  /// No description provided for @notificationsMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get notificationsMarkAllRead;

  /// No description provided for @notificationsErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load notifications'**
  String get notificationsErrorTitle;

  /// No description provided for @notificationActionError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update. Please try again.'**
  String get notificationActionError;

  /// No description provided for @accountShowClosetTitle.
  ///
  /// In en, this message translates to:
  /// **'Show closet publicly'**
  String get accountShowClosetTitle;

  /// No description provided for @accountShowClosetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Let others browse your closet pieces on your public profile.'**
  String get accountShowClosetSubtitle;

  /// No description provided for @creditsSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Your try-on credits'**
  String get creditsSheetTitle;

  /// No description provided for @creditsSheetFreeLeft.
  ///
  /// In en, this message translates to:
  /// **'{count} free AI try-ons left'**
  String creditsSheetFreeLeft(int count);

  /// No description provided for @creditsSheetBalance.
  ///
  /// In en, this message translates to:
  /// **'{count} purchased credits'**
  String creditsSheetBalance(int count);

  /// No description provided for @creditsSheetReset.
  ///
  /// In en, this message translates to:
  /// **'A one-time free trial. Upgrade for unlimited AI try-ons.'**
  String get creditsSheetReset;

  /// No description provided for @creditsSheetUpgrade.
  ///
  /// In en, this message translates to:
  /// **'Get more with Premium'**
  String get creditsSheetUpgrade;

  /// No description provided for @creditsSheetUnlimited.
  ///
  /// In en, this message translates to:
  /// **'You\'re on Premium — enjoy your try-ons.'**
  String get creditsSheetUnlimited;

  /// No description provided for @premiumComparisonTitle.
  ///
  /// In en, this message translates to:
  /// **'Free · Pro · Pro Max'**
  String get premiumComparisonTitle;

  /// No description provided for @premiumCompareFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get premiumCompareFree;

  /// No description provided for @premiumComparePremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get premiumComparePremium;

  /// No description provided for @premiumComparePro.
  ///
  /// In en, this message translates to:
  /// **'Pro'**
  String get premiumComparePro;

  /// No description provided for @premiumCompareProMax.
  ///
  /// In en, this message translates to:
  /// **'Pro Max'**
  String get premiumCompareProMax;

  /// No description provided for @premiumFeatureRealistic.
  ///
  /// In en, this message translates to:
  /// **'AI Realistic Try-On'**
  String get premiumFeatureRealistic;

  /// No description provided for @premiumFeatureHd.
  ///
  /// In en, this message translates to:
  /// **'HD / Try-On Max'**
  String get premiumFeatureHd;

  /// No description provided for @premiumFeatureSaveShare.
  ///
  /// In en, this message translates to:
  /// **'Save & share looks'**
  String get premiumFeatureSaveShare;

  /// No description provided for @premiumFeaturePriority.
  ///
  /// In en, this message translates to:
  /// **'Priority rendering'**
  String get premiumFeaturePriority;

  /// No description provided for @premiumFeatureCredits.
  ///
  /// In en, this message translates to:
  /// **'AI realistic try-ons'**
  String get premiumFeatureCredits;

  /// No description provided for @premiumCreditsFree.
  ///
  /// In en, this message translates to:
  /// **'3 free'**
  String get premiumCreditsFree;

  /// No description provided for @premiumCreditsPro.
  ///
  /// In en, this message translates to:
  /// **'75/mo'**
  String get premiumCreditsPro;

  /// No description provided for @premiumCreditsProMax.
  ///
  /// In en, this message translates to:
  /// **'150/mo'**
  String get premiumCreditsProMax;

  /// No description provided for @premiumCreditsPremium.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get premiumCreditsPremium;

  /// No description provided for @premiumFeatureWardrobe.
  ///
  /// In en, this message translates to:
  /// **'Unlimited wardrobe'**
  String get premiumFeatureWardrobe;

  /// No description provided for @premiumFeatureDrawers.
  ///
  /// In en, this message translates to:
  /// **'Wardrobe drawers'**
  String get premiumFeatureDrawers;

  /// No description provided for @premiumDrawersFree.
  ///
  /// In en, this message translates to:
  /// **'3'**
  String get premiumDrawersFree;

  /// No description provided for @premiumDrawersPremium.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get premiumDrawersPremium;

  /// No description provided for @premiumRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore purchase'**
  String get premiumRestore;

  /// No description provided for @drawerLockedBadge.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get drawerLockedBadge;

  /// No description provided for @drawerLockedTapHint.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Premium to open this drawer'**
  String get drawerLockedTapHint;

  /// No description provided for @catGroupTops.
  ///
  /// In en, this message translates to:
  /// **'Tops'**
  String get catGroupTops;

  /// No description provided for @catGroupBottoms.
  ///
  /// In en, this message translates to:
  /// **'Bottoms'**
  String get catGroupBottoms;

  /// No description provided for @catGroupOnePiece.
  ///
  /// In en, this message translates to:
  /// **'One-piece'**
  String get catGroupOnePiece;

  /// No description provided for @catGroupOuterwear.
  ///
  /// In en, this message translates to:
  /// **'Outerwear'**
  String get catGroupOuterwear;

  /// No description provided for @catGroupFootwear.
  ///
  /// In en, this message translates to:
  /// **'Footwear'**
  String get catGroupFootwear;

  /// No description provided for @catGroupModest.
  ///
  /// In en, this message translates to:
  /// **'Modest'**
  String get catGroupModest;

  /// No description provided for @catGroupAccessories.
  ///
  /// In en, this message translates to:
  /// **'Bags & Accessories'**
  String get catGroupAccessories;

  /// No description provided for @catGroupLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Lifestyle'**
  String get catGroupLifestyle;

  /// No description provided for @catGroupOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get catGroupOther;

  /// No description provided for @catTops.
  ///
  /// In en, this message translates to:
  /// **'Tops'**
  String get catTops;

  /// No description provided for @catTshirts.
  ///
  /// In en, this message translates to:
  /// **'T-Shirts'**
  String get catTshirts;

  /// No description provided for @catShirts.
  ///
  /// In en, this message translates to:
  /// **'Shirts'**
  String get catShirts;

  /// No description provided for @catBlouses.
  ///
  /// In en, this message translates to:
  /// **'Blouses'**
  String get catBlouses;

  /// No description provided for @catTunics.
  ///
  /// In en, this message translates to:
  /// **'Tunics/Kurtis'**
  String get catTunics;

  /// No description provided for @catBottoms.
  ///
  /// In en, this message translates to:
  /// **'Bottoms'**
  String get catBottoms;

  /// No description provided for @catPants.
  ///
  /// In en, this message translates to:
  /// **'Pants'**
  String get catPants;

  /// No description provided for @catJeans.
  ///
  /// In en, this message translates to:
  /// **'Jeans'**
  String get catJeans;

  /// No description provided for @catSkirts.
  ///
  /// In en, this message translates to:
  /// **'Skirts'**
  String get catSkirts;

  /// No description provided for @catShorts.
  ///
  /// In en, this message translates to:
  /// **'Shorts'**
  String get catShorts;

  /// No description provided for @catDresses.
  ///
  /// In en, this message translates to:
  /// **'Dresses'**
  String get catDresses;

  /// No description provided for @catTraditional.
  ///
  /// In en, this message translates to:
  /// **'Traditional'**
  String get catTraditional;

  /// No description provided for @catOuterwear.
  ///
  /// In en, this message translates to:
  /// **'Outerwear'**
  String get catOuterwear;

  /// No description provided for @catWinter.
  ///
  /// In en, this message translates to:
  /// **'Winter'**
  String get catWinter;

  /// No description provided for @catShoes.
  ///
  /// In en, this message translates to:
  /// **'Shoes'**
  String get catShoes;

  /// No description provided for @catHijab.
  ///
  /// In en, this message translates to:
  /// **'Hijab'**
  String get catHijab;

  /// No description provided for @catScarves.
  ///
  /// In en, this message translates to:
  /// **'Scarves'**
  String get catScarves;

  /// No description provided for @catBags.
  ///
  /// In en, this message translates to:
  /// **'Bags'**
  String get catBags;

  /// No description provided for @catEyewear.
  ///
  /// In en, this message translates to:
  /// **'Eyewear'**
  String get catEyewear;

  /// No description provided for @catJewelry.
  ///
  /// In en, this message translates to:
  /// **'Jewelry'**
  String get catJewelry;

  /// No description provided for @catBelts.
  ///
  /// In en, this message translates to:
  /// **'Belts'**
  String get catBelts;

  /// No description provided for @catHats.
  ///
  /// In en, this message translates to:
  /// **'Hats'**
  String get catHats;

  /// No description provided for @catAccessories.
  ///
  /// In en, this message translates to:
  /// **'Accessories'**
  String get catAccessories;

  /// No description provided for @catActivewear.
  ///
  /// In en, this message translates to:
  /// **'Activewear'**
  String get catActivewear;

  /// No description provided for @catSleepwear.
  ///
  /// In en, this message translates to:
  /// **'Sleepwear'**
  String get catSleepwear;

  /// No description provided for @catSwimwear.
  ///
  /// In en, this message translates to:
  /// **'Swimwear'**
  String get catSwimwear;

  /// No description provided for @catWorkwear.
  ///
  /// In en, this message translates to:
  /// **'Workwear'**
  String get catWorkwear;

  /// No description provided for @catParty.
  ///
  /// In en, this message translates to:
  /// **'Party'**
  String get catParty;

  /// No description provided for @catTravel.
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get catTravel;

  /// No description provided for @catOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get catOther;

  /// No description provided for @catMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get catMore;

  /// No description provided for @catPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a category'**
  String get catPickerTitle;

  /// No description provided for @catPickerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search categories'**
  String get catPickerSearchHint;

  /// No description provided for @drawerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search drawers'**
  String get drawerSearchHint;

  /// No description provided for @drawerSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No drawers match'**
  String get drawerSearchEmpty;

  /// No description provided for @addItemPhotoHint.
  ///
  /// In en, this message translates to:
  /// **'A clear photo of one clothing item works best'**
  String get addItemPhotoHint;

  /// No description provided for @categorizeTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit details'**
  String get categorizeTitle;

  /// No description provided for @categorizeNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get categorizeNameLabel;

  /// No description provided for @categorizeNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. White linen shirt'**
  String get categorizeNameHint;

  /// No description provided for @categorizeCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get categorizeCategoryLabel;

  /// No description provided for @categorizeColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get categorizeColorLabel;

  /// No description provided for @categorizeSave.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get categorizeSave;

  /// No description provided for @categorizeSaved.
  ///
  /// In en, this message translates to:
  /// **'Item updated'**
  String get categorizeSaved;

  /// No description provided for @categorizeError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save changes'**
  String get categorizeError;

  /// No description provided for @categorizeDrawerNone.
  ///
  /// In en, this message translates to:
  /// **'No drawer'**
  String get categorizeDrawerNone;

  /// No description provided for @categorizeEditDetails.
  ///
  /// In en, this message translates to:
  /// **'Edit details'**
  String get categorizeEditDetails;

  /// No description provided for @categorizePromptBody.
  ///
  /// In en, this message translates to:
  /// **'Add a category so this piece sorts into the right drawer.'**
  String get categorizePromptBody;

  /// No description provided for @categorizeAction.
  ///
  /// In en, this message translates to:
  /// **'Categorize'**
  String get categorizeAction;

  /// No description provided for @closetNeedsCategory.
  ///
  /// In en, this message translates to:
  /// **'Needs category'**
  String get closetNeedsCategory;

  /// No description provided for @slotTop.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get slotTop;

  /// No description provided for @slotBottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get slotBottom;

  /// No description provided for @slotDress.
  ///
  /// In en, this message translates to:
  /// **'Dress'**
  String get slotDress;

  /// No description provided for @slotOuterwear.
  ///
  /// In en, this message translates to:
  /// **'Outerwear'**
  String get slotOuterwear;

  /// No description provided for @slotShoes.
  ///
  /// In en, this message translates to:
  /// **'Shoes'**
  String get slotShoes;

  /// No description provided for @slotBag.
  ///
  /// In en, this message translates to:
  /// **'Bag'**
  String get slotBag;

  /// No description provided for @slotHijabScarf.
  ///
  /// In en, this message translates to:
  /// **'Hijab / Scarf'**
  String get slotHijabScarf;

  /// No description provided for @slotEyewear.
  ///
  /// In en, this message translates to:
  /// **'Eyewear'**
  String get slotEyewear;

  /// No description provided for @slotJewelry.
  ///
  /// In en, this message translates to:
  /// **'Jewelry & accessories'**
  String get slotJewelry;

  /// No description provided for @outfitEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit outfit'**
  String get outfitEditTitle;

  /// No description provided for @outfitBuilderPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Build your look'**
  String get outfitBuilderPickTitle;

  /// No description provided for @outfitBuilderPickSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add pieces to each slot to create a full outfit set.'**
  String get outfitBuilderPickSubtitle;

  /// No description provided for @outfitBuilderOtherPieces.
  ///
  /// In en, this message translates to:
  /// **'Other pieces'**
  String get outfitBuilderOtherPieces;

  /// No description provided for @outfitTryFullLook.
  ///
  /// In en, this message translates to:
  /// **'Try full look'**
  String get outfitTryFullLook;

  /// No description provided for @outfitUpdated.
  ///
  /// In en, this message translates to:
  /// **'Outfit updated'**
  String get outfitUpdated;

  /// No description provided for @outfitSlotAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a piece'**
  String get outfitSlotAdd;

  /// No description provided for @outfitSlotRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get outfitSlotRemove;

  /// Title of the closet picker for one outfit slot.
  ///
  /// In en, this message translates to:
  /// **'Choose a {slot}'**
  String outfitPickForSlot(String slot);

  /// No description provided for @outfitShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get outfitShowAll;

  /// No description provided for @outfitShowMatching.
  ///
  /// In en, this message translates to:
  /// **'Show matching'**
  String get outfitShowMatching;

  /// No description provided for @outfitEditAction.
  ///
  /// In en, this message translates to:
  /// **'Edit outfit'**
  String get outfitEditAction;

  /// No description provided for @outfitDetailMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'Pieces no longer in your closet'**
  String get outfitDetailMissingTitle;

  /// No description provided for @outfitDetailMissingBody.
  ///
  /// In en, this message translates to:
  /// **'The items in this outfit have been removed. Edit it to pick new pieces.'**
  String get outfitDetailMissingBody;

  /// No description provided for @outfitFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get outfitFavorite;

  /// No description provided for @outfitUnfavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get outfitUnfavorite;

  /// No description provided for @profileStatFollowers.
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get profileStatFollowers;

  /// No description provided for @profileStatFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get profileStatFollowing;

  /// No description provided for @packingDestinationLabel.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get packingDestinationLabel;

  /// No description provided for @packingDestinationHint.
  ///
  /// In en, this message translates to:
  /// **'City or country (optional)'**
  String get packingDestinationHint;

  /// No description provided for @packingClimateLabel.
  ///
  /// In en, this message translates to:
  /// **'Climate'**
  String get packingClimateLabel;

  /// No description provided for @packingClimateHot.
  ///
  /// In en, this message translates to:
  /// **'Hot'**
  String get packingClimateHot;

  /// No description provided for @packingClimateCold.
  ///
  /// In en, this message translates to:
  /// **'Cold'**
  String get packingClimateCold;

  /// No description provided for @packingClimateRainy.
  ///
  /// In en, this message translates to:
  /// **'Rainy'**
  String get packingClimateRainy;

  /// No description provided for @packingClimateMixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get packingClimateMixed;

  /// No description provided for @packingActivitiesLabel.
  ///
  /// In en, this message translates to:
  /// **'Activities'**
  String get packingActivitiesLabel;

  /// No description provided for @packingActivityCasual.
  ///
  /// In en, this message translates to:
  /// **'Casual'**
  String get packingActivityCasual;

  /// No description provided for @packingActivityWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get packingActivityWork;

  /// No description provided for @packingActivityUniversity.
  ///
  /// In en, this message translates to:
  /// **'University'**
  String get packingActivityUniversity;

  /// No description provided for @packingActivityParty.
  ///
  /// In en, this message translates to:
  /// **'Party'**
  String get packingActivityParty;

  /// No description provided for @packingActivityBeach.
  ///
  /// In en, this message translates to:
  /// **'Beach'**
  String get packingActivityBeach;

  /// No description provided for @packingActivityWedding.
  ///
  /// In en, this message translates to:
  /// **'Wedding'**
  String get packingActivityWedding;

  /// No description provided for @packingActivityTravel.
  ///
  /// In en, this message translates to:
  /// **'Travel day'**
  String get packingActivityTravel;

  /// No description provided for @packingLaundryLabel.
  ///
  /// In en, this message translates to:
  /// **'Laundry access'**
  String get packingLaundryLabel;

  /// No description provided for @packingLaundrySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pack lighter — you can re-wash on the trip'**
  String get packingLaundrySubtitle;

  /// No description provided for @packingModestLabel.
  ///
  /// In en, this message translates to:
  /// **'Modest / hijab-friendly'**
  String get packingModestLabel;

  /// No description provided for @packingModestSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Prioritise modest, hijab-friendly pieces'**
  String get packingModestSubtitle;

  /// Progress counter on the packing result.
  ///
  /// In en, this message translates to:
  /// **'{packed} of {total} packed'**
  String packingPackedCount(int packed, int total);

  /// No description provided for @packingMissingPieces.
  ///
  /// In en, this message translates to:
  /// **'Your closet is a little light for this trip. Add a few versatile pieces and plan again.'**
  String get packingMissingPieces;

  /// No description provided for @packingGroupTops.
  ///
  /// In en, this message translates to:
  /// **'Tops'**
  String get packingGroupTops;

  /// No description provided for @packingGroupBottoms.
  ///
  /// In en, this message translates to:
  /// **'Bottoms'**
  String get packingGroupBottoms;

  /// No description provided for @packingGroupDresses.
  ///
  /// In en, this message translates to:
  /// **'Dresses & tunics'**
  String get packingGroupDresses;

  /// No description provided for @packingGroupOuterwear.
  ///
  /// In en, this message translates to:
  /// **'Outerwear'**
  String get packingGroupOuterwear;

  /// No description provided for @packingGroupShoes.
  ///
  /// In en, this message translates to:
  /// **'Shoes'**
  String get packingGroupShoes;

  /// No description provided for @packingGroupBags.
  ///
  /// In en, this message translates to:
  /// **'Bags'**
  String get packingGroupBags;

  /// No description provided for @packingGroupHijab.
  ///
  /// In en, this message translates to:
  /// **'Hijab & scarves'**
  String get packingGroupHijab;

  /// No description provided for @packingGroupAccessories.
  ///
  /// In en, this message translates to:
  /// **'Accessories'**
  String get packingGroupAccessories;

  /// No description provided for @packingGroupEssentials.
  ///
  /// In en, this message translates to:
  /// **'Essentials'**
  String get packingGroupEssentials;
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
