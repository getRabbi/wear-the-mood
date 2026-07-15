import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_providers.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/auth/set_password_screen.dart';
import '../../features/community/leaderboard_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/challenges/challenge_detail_screen.dart';
import '../../features/challenges/challenges_screen.dart';
import '../../features/dev/component_gallery_screen.dart';
import '../../ui/closet/wtm_add_garment_screen.dart';
import '../../ui/closet/wtm_closet_screen.dart';
import '../../ui/auth/wtm_auth_screen.dart';
import '../../ui/auth/wtm_onboarding_screen.dart';
import '../../ui/auth/wtm_splash_screen.dart';
import '../../ui/closet/wtm_garment_detail_screen.dart';
import '../../ui/community/wtm_compose_screen.dart';
import '../../ui/community/wtm_post_detail_screen.dart';
import '../../ui/community/wtm_public_profile_screen.dart';
import '../../ui/community/wtm_saved_posts_screen.dart';
import '../../ui/community/wtm_social_screen.dart';
import '../../ui/discover/wtm_giveaway_chat_screen.dart';
import '../../ui/discover/wtm_giveaways_screen.dart';
import '../../ui/discover/wtm_inbox_screen.dart';
import '../../ui/discover/wtm_newsroom_screen.dart';
import '../../ui/discover/wtm_offers_screen.dart';
import '../../ui/discover/wtm_search_screen.dart';
import '../../ui/home/wtm_home_screen.dart';
import '../../ui/mirror/wtm_mirror_adjust.dart';
import '../../ui/mirror/wtm_mirror_generating.dart';
import '../../ui/mirror/wtm_mirror_result.dart';
import '../../ui/mirror/wtm_body_photo_screen.dart';
import '../../ui/mirror/wtm_mirror_step1.dart';
import '../../ui/mirror/wtm_mirror_step2.dart';
import '../../ui/mirror/wtm_mirror_step3.dart';
import '../../ui/outfits/wtm_outfit_detail_screen.dart';
import '../../ui/outfits/wtm_outfits_screen.dart';
import '../../ui/notifications/wtm_notification_prefs_screen.dart';
import '../../ui/paywall/wtm_paywall_screen.dart';
import '../../ui/referral/wtm_referral_screen.dart';
import '../../ui/profile/wtm_looks_screen.dart';
import '../../ui/profile/wtm_profile_edit_screen.dart';
import '../../ui/profile/wtm_profile_screen.dart';
import '../../ui/profile/wtm_settings_screen.dart';
import '../../ui/shell/wtm_shell.dart';
import '../../ui/stylist/wtm_stylist_look_screen.dart';
import '../../ui/stylist/wtm_stylist_screen.dart';
import '../../ui/stubs/stubs_system.dart';
import '../../data/models/outfit.dart';
import '../../data/models/post.dart';
import '../../features/news/news_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/onboarding/root_gate.dart';
import '../../features/outfits/create_outfit_screen.dart';
import '../../features/outfits/outfit_detail_screen.dart';
import '../../features/packing/packing_screen.dart';
import '../../features/profile/account_details_screen.dart';
import '../../features/profile/avatar_screen.dart';
import '../../data/models/wardrobe_item.dart';
import '../../features/wardrobe/add_wardrobe_item_screen.dart';
import '../../features/wardrobe/categorize_item_screen.dart';
import '../../features/wardrobe/closet_item_detail_screen.dart';
import '../../features/wardrobe/drawers/drawer_detail_screen.dart';
import '../../features/wardrobe/wardrobe_insights_screen.dart';
import '../../features/outfits/outfits_screen.dart';
import '../../features/paywall/paywall_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/referral/referral_screen.dart';
import '../../features/social/compose_post_screen.dart';
import '../../features/social/follow_list_screen.dart';
import '../../features/social/public_profile_screen.dart';
import '../../features/stylist/stylist_screen.dart';
import '../../features/studio/ai_looks_screen.dart';
import '../../features/tryon/tryon_history_screen.dart';
import '../../features/tryon/tryon_screen.dart';
import '../../features/tryon/two_d/two_d_editor_screen.dart';
import '../../data/models/daily_guide.dart';
import '../../features/giveaway/create_giveaway_screen.dart';
import '../../features/giveaway/giveaway_detail_screen.dart';
import '../../features/giveaway/giveaways_mine_screen.dart';
import '../../features/guide/daily_guide_screen.dart';
import '../../features/quiz/style_quiz_screen.dart';
import '../../features/wardrobe/wardrobe_screen.dart';
import 'app_transitions.dart';
import 'routes.dart';

/// Pre-auth surfaces a logged-out user may reach. Everything else redirects to
/// the welcome/sign-in gate (`/`, served by RootGate). `/` itself shows the
/// value carousel or the welcome screen; `/auth` + `/set-password` are the
/// sign-in / password-recovery flows. Legal pages are external (hosted) URLs.
const _publicRoutes = {
  AppRoute.home,
  AppRoute.auth,
  AppRoute.setPassword,
};

/// DEV-ONLY launcher for the WTM component gallery: run with
/// `--dart-define=DEV_GALLERY=true` to boot straight into `/dev/gallery`
/// (debug builds only — the route doesn't exist otherwise).
const _launchDevGallery = bool.fromEnvironment('DEV_GALLERY');

/// The WTM Atelier shell is the DEFAULT app shell on this branch (mobile-QA
/// cutover): splash → auth → home all run in WTM, in every build mode. Pass
/// `--dart-define=WTM_SHELL=false` only to fall back to the legacy shell.
const _launchWtmShell = bool.fromEnvironment('WTM_SHELL', defaultValue: true);

/// WTM surfaces a logged-out user may reach — the WTM auth gate (§3.A).
/// Everything else (WTM or legacy) requires a session and redirects here.
const _wtmPublicRoutes = {
  AppRoute.wtmSplash,
  AppRoute.wtmAuth,
  AppRoute.wtmOnboarding,
  AppRoute.setPassword,
};

/// App router, exposed via Riverpod so it reacts to auth state. The redirect is
/// the client-side auth gate (CLAUDE.md §11): logged-out users only reach the
/// pre-auth surfaces above; the backend (RLS + JWT) stays the real boundary.
final goRouterProvider = Provider<GoRouter>((ref) {
  // Bridge auth changes → a Listenable so go_router re-runs [redirect] on every
  // sign-in / sign-out (kicking the user into, or out of, the gate).
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen(isAuthenticatedProvider, (_, _) => refresh.value++);

  return GoRouter(
    initialLocation: _launchWtmShell
        ? AppRoute.wtmSplash
        : (kDebugMode && _launchDevGallery)
            ? AppRoute.devGallery
            : AppRoute.home,
    debugLogDiagnostics: true,
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(isAuthenticatedProvider);
      final loc = state.matchedLocation;
      // The dev gallery stays a gate-free debug tool.
      if (kDebugMode && loc == AppRoute.devGallery) return null;

      if (_launchWtmShell) {
        // WTM cutover gate (URGENT auth regression fix): the shell is a real
        // product surface now — signed-out users land on the WTM auth gate
        // (never an ungated shell firing "Missing bearer token" calls), and
        // signed-in users can never fall back into the legacy shell entries
        // (`/`, `/auth`) after logout/login.
        if (!loggedIn) {
          return _wtmPublicRoutes.contains(loc) ? null : AppRoute.wtmAuth;
        }
        if (loc == AppRoute.auth ||
            loc == AppRoute.wtmAuth ||
            loc == AppRoute.home) {
          return AppRoute.wtmHome;
        }
        return null;
      }

      if (!loggedIn) {
        // Logged out: allow only the gate surfaces; bounce the rest to `/`.
        return _publicRoutes.contains(loc) ? null : AppRoute.home;
      }
      // Logged in: don't strand the user on the sign-in screen.
      return loc == AppRoute.auth ? AppRoute.home : null;
    },
    routes: [
      GoRoute(
        path: AppRoute.home,
        name: AppRoute.homeName,
        builder: (context, state) => const RootGate(),
      ),
      GoRoute(
        path: AppRoute.tryon,
        name: AppRoute.tryonName,
        builder: (context, state) => const TryOnScreen(),
      ),
      GoRoute(
        path: AppRoute.tryonHistory,
        name: AppRoute.tryonHistoryName,
        pageBuilder: (context, state) =>
            appSharedAxisPage(child: const TryOnHistoryScreen()),
      ),
      GoRoute(
        path: AppRoute.tryon2dEditor,
        name: AppRoute.tryon2dEditorName,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! TwoDEditorArgs) return const TryOnScreen();
          return TwoDEditorScreen(args: extra);
        },
      ),
      GoRoute(
        path: AppRoute.aiLooks,
        name: AppRoute.aiLooksName,
        pageBuilder: (context, state) =>
            appSharedAxisPage(child: const AiLooksScreen()),
      ),
      GoRoute(
        path: AppRoute.leaderboard,
        name: AppRoute.leaderboardName,
        pageBuilder: (context, state) =>
            appSharedAxisPage(child: const LeaderboardScreen()),
      ),
      GoRoute(
        path: AppRoute.wardrobe,
        name: AppRoute.wardrobeName,
        builder: (context, state) => const WardrobeScreen(),
        routes: [
          GoRoute(
            path: 'add',
            name: AppRoute.wardrobeAddName,
            builder: (context, state) => AddWardrobeItemScreen(
              presetDrawerId: state.extra is String ? state.extra as String : null,
            ),
          ),
          GoRoute(
            path: 'drawer/:id',
            name: AppRoute.wardrobeDrawerName,
            builder: (context, state) =>
                DrawerDetailScreen(drawerId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'insights',
            name: AppRoute.wardrobeInsightsName,
            pageBuilder: (context, state) =>
                appSharedAxisPage(child: const WardrobeInsightsScreen()),
          ),
          GoRoute(
            path: 'item',
            name: AppRoute.wardrobeItemName,
            builder: (context, state) {
              final extra = state.extra;
              if (extra is! WardrobeItem) return const WardrobeScreen();
              return ClosetItemDetailScreen(item: extra);
            },
          ),
          GoRoute(
            path: 'categorize',
            name: AppRoute.wardrobeCategorizeName,
            builder: (context, state) {
              final extra = state.extra;
              if (extra is! WardrobeItem) return const WardrobeScreen();
              return CategorizeItemScreen(item: extra);
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoute.stylist,
        name: AppRoute.stylistName,
        builder: (context, state) => const StylistScreen(),
      ),
      GoRoute(
        path: AppRoute.socialCompose,
        name: AppRoute.socialComposeName,
        builder: (context, state) {
          final args = state.extra;
          return ComposePostScreen(
            challengeId: args is ComposeArgs ? args.challengeId : null,
            challengeTitle: args is ComposeArgs ? args.challengeTitle : null,
            presetPhoto: args is ComposeArgs ? args.presetPhoto : null,
            editPost: args is ComposeArgs ? args.editPost : null,
          );
        },
      ),
      GoRoute(
        path: AppRoute.styleQuiz,
        name: AppRoute.styleQuizName,
        builder: (context, state) => const StyleQuizScreen(),
      ),
      GoRoute(
        path: AppRoute.dailyGuide,
        name: AppRoute.dailyGuideName,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! DailyGuide) return const RootGate();
          return DailyGuideScreen(guide: extra);
        },
      ),
      GoRoute(
        path: AppRoute.giveawayCreate,
        name: AppRoute.giveawayCreateName,
        pageBuilder: (context, state) {
          final extra = state.extra;
          return appSharedAxisPage(
            child: CreateGiveawayScreen(
              item: extra is WardrobeItem ? extra : null,
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoute.giveawayDetail,
        name: AppRoute.giveawayDetailName,
        pageBuilder: (context, state) {
          final extra = state.extra;
          return appSharedAxisPage(
            child: extra is String
                ? GiveawayDetailScreen(giveawayId: extra)
                : const RootGate(),
          );
        },
      ),
      GoRoute(
        path: AppRoute.giveawaysMine,
        name: AppRoute.giveawaysMineName,
        pageBuilder: (context, state) =>
            appSharedAxisPage(child: const GiveawaysMineScreen()),
      ),
      GoRoute(
        path: AppRoute.challenges,
        name: AppRoute.challengesName,
        builder: (context, state) => const ChallengesScreen(),
        routes: [
          GoRoute(
            path: ':slug',
            name: AppRoute.challengeDetailName,
            builder: (context, state) =>
                ChallengeDetailScreen(slug: state.pathParameters['slug']!),
          ),
        ],
      ),
      GoRoute(
        path: AppRoute.news,
        name: AppRoute.newsName,
        pageBuilder: (context, state) =>
            appSharedAxisPage(child: const NewsScreen()),
      ),
      GoRoute(
        path: AppRoute.referrals,
        name: AppRoute.referralsName,
        pageBuilder: (context, state) =>
            appSharedAxisPage(child: const ReferralScreen()),
      ),
      GoRoute(
        path: AppRoute.packing,
        name: AppRoute.packingName,
        pageBuilder: (context, state) =>
            appSharedAxisPage(child: const PackingScreen()),
      ),
      GoRoute(
        path: AppRoute.calendar,
        name: AppRoute.calendarName,
        pageBuilder: (context, state) =>
            appSharedAxisPage(child: const CalendarScreen()),
      ),
      GoRoute(
        path: AppRoute.outfits,
        name: AppRoute.outfitsName,
        builder: (context, state) => const OutfitsScreen(),
        routes: [
          GoRoute(
            path: 'create',
            name: AppRoute.outfitsCreateName,
            // The same builder edits when handed an existing Outfit as `extra`.
            builder: (context, state) => CreateOutfitScreen(
              existing: state.extra is Outfit ? state.extra as Outfit : null,
            ),
          ),
          GoRoute(
            path: 'detail',
            name: AppRoute.outfitsDetailName,
            builder: (context, state) {
              final extra = state.extra;
              if (extra is! Outfit) return const OutfitsScreen();
              return OutfitDetailScreen(outfit: extra);
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoute.auth,
        name: AppRoute.authName,
        // `extra == true` opens straight into sign-up (from "Create account").
        builder: (context, state) =>
            AuthScreen(initialSignUp: state.extra is bool && state.extra as bool),
      ),
      GoRoute(
        path: AppRoute.setPassword,
        name: AppRoute.setPasswordName,
        builder: (context, state) => const SetPasswordScreen(),
      ),
      GoRoute(
        path: AppRoute.notifications,
        name: AppRoute.notificationsName,
        pageBuilder: (context, state) =>
            appSharedAxisPage(child: const NotificationsScreen()),
      ),
      GoRoute(
        path: AppRoute.profile,
        name: AppRoute.profileName,
        pageBuilder: (context, state) =>
            appSharedAxisPage(child: const ProfileScreen()),
      ),
      GoRoute(
        path: '${AppRoute.userProfile}/:userId',
        name: AppRoute.userProfileName,
        builder: (context, state) => PublicProfileScreen(
          userId: state.pathParameters['userId']!,
          initialName: state.extra is String ? state.extra as String : null,
        ),
        routes: [
          GoRoute(
            path: 'followers',
            name: AppRoute.userFollowersName,
            builder: (context, state) => FollowListScreen(
              userId: state.pathParameters['userId']!,
              mode: FollowListMode.followers,
            ),
          ),
          GoRoute(
            path: 'following',
            name: AppRoute.userFollowingName,
            builder: (context, state) => FollowListScreen(
              userId: state.pathParameters['userId']!,
              mode: FollowListMode.following,
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoute.avatar,
        name: AppRoute.avatarName,
        builder: (context, state) => const AvatarScreen(),
      ),
      GoRoute(
        path: AppRoute.accountDetails,
        name: AppRoute.accountDetailsName,
        pageBuilder: (context, state) =>
            appSharedAxisPage(child: const AccountDetailsScreen()),
      ),
      GoRoute(
        path: AppRoute.paywall,
        name: AppRoute.paywallName,
        builder: (context, state) => const PaywallScreen(),
      ),
      // DEV-ONLY: WTM component gallery (UI_IMPLEMENTATION.md P0 gate).
      // Compiled out of release/profile builds.
      if (kDebugMode)
        GoRoute(
          path: AppRoute.devGallery,
          name: AppRoute.devGalleryName,
          builder: (context, state) => const ComponentGalleryScreen(),
        ),
      // ---- WTM Atelier shell (UI_IMPLEMENTATION.md §2/§5 P1) ----
      // CUT OVER: the default shell in every build mode (URGENT auth fix —
      // it was debug-only, so a release build silently fell back to legacy).
      // Four stateful branches under the persistent nav (Home · Social ·
      // [orb] · Inbox · Profile); the orb is a sheet, not a branch.
      // Full-bleed flow screens live OUTSIDE the shell below.
      if (_launchWtmShell)
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              WtmShell(shell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoute.wtmHome,
                  name: AppRoute.wtmHomeName,
                  // P2: the real Home (board 01). Stubs remain downstream.
                  builder: (context, state) => const WtmHomeScreen(),
                ),
                GoRoute(
                  path: AppRoute.wtmMirror,
                  name: AppRoute.wtmMirrorName,
                  // P4: the real MoodMirror on the shipped try-on stack.
                  builder: (context, state) => const WtmMirrorStep1Screen(),
                  routes: [
                    GoRoute(
                      path: 'garments',
                      name: AppRoute.wtmMirrorGarmentsName,
                      builder: (context, state) =>
                          const WtmMirrorStep2Screen(),
                    ),
                    GoRoute(
                      path: 'mode',
                      name: AppRoute.wtmMirrorModeName,
                      builder: (context, state) =>
                          const WtmMirrorStep3Screen(),
                    ),
                  ],
                ),
                GoRoute(
                  path: AppRoute.wtmCloset,
                  name: AppRoute.wtmClosetName,
                  // P3: the real closet (board 02) on live wardrobe data.
                  builder: (context, state) => const WtmClosetScreen(),
                  routes: [
                    GoRoute(
                      path: 'item',
                      name: AppRoute.wtmClosetItemName,
                      builder: (context, state) {
                        final extra = state.extra;
                        if (extra is! WardrobeItem) {
                          return const WtmClosetScreen();
                        }
                        return WtmGarmentDetailScreen(item: extra);
                      },
                    ),
                    GoRoute(
                      path: 'add',
                      name: AppRoute.wtmClosetAddName,
                      builder: (context, state) =>
                          const WtmAddGarmentScreen(),
                    ),
                  ],
                ),
                GoRoute(
                  path: AppRoute.wtmStylist,
                  name: AppRoute.wtmStylistName,
                  // P5: the real AI Stylist on the shipped stylist backend.
                  builder: (context, state) => const WtmStylistScreen(),
                  routes: [
                    GoRoute(
                      path: 'look',
                      name: AppRoute.wtmStylistLookName,
                      builder: (context, state) =>
                          const WtmStylistLookScreen(),
                    ),
                  ],
                ),
                GoRoute(
                  path: AppRoute.wtmOutfits,
                  name: AppRoute.wtmOutfitsName,
                  // P5: the real Outfit Maker (saved grid + composer).
                  builder: (context, state) => const WtmOutfitsScreen(),
                  routes: [
                    GoRoute(
                      path: 'detail',
                      name: AppRoute.wtmOutfitDetailName,
                      builder: (context, state) {
                        final extra = state.extra;
                        if (extra is! Outfit) return const WtmOutfitsScreen();
                        return WtmOutfitDetailScreen(outfit: extra);
                      },
                    ),
                  ],
                ),
                GoRoute(
                  path: AppRoute.wtmLooks,
                  name: AppRoute.wtmLooksName,
                  // P7: the real Saved Looks gallery.
                  builder: (context, state) => const WtmLooksScreen(),
                ),
                GoRoute(
                  path: AppRoute.wtmGiveaways,
                  name: AppRoute.wtmGiveawaysName,
                  // P9: real giveaways browse + detail (`?id=`).
                  builder: (context, state) => const WtmGiveawaysScreen(),
                  routes: [
                    GoRoute(
                      path: 'detail',
                      name: AppRoute.wtmGiveawayDetailName,
                      builder: (context, state) => WtmGiveawayDetailScreen(
                        id: state.uri.queryParameters['id'] ?? '',
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: AppRoute.wtmOffers,
                  name: AppRoute.wtmOffersName,
                  // P9: real offers + detail (`?id=` → affiliate).
                  builder: (context, state) => const WtmOffersScreen(),
                  routes: [
                    GoRoute(
                      path: 'detail',
                      name: AppRoute.wtmOfferDetailName,
                      builder: (context, state) => WtmOfferDetailScreen(
                        id: state.uri.queryParameters['id'] ?? '',
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: AppRoute.wtmNewsroom,
                  name: AppRoute.wtmNewsroomName,
                  // P9: real newsroom + article reader (`?id=`).
                  builder: (context, state) => const WtmNewsroomScreen(),
                  routes: [
                    GoRoute(
                      path: 'article',
                      name: AppRoute.wtmArticleName,
                      builder: (context, state) => WtmArticleScreen(
                        id: state.uri.queryParameters['id'] ?? '',
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: AppRoute.wtmSearch,
                  name: AppRoute.wtmSearchName,
                  // P9: real scoped search (closet / community / brands).
                  builder: (context, state) => WtmSearchScreen(
                    initialScope: state.uri.queryParameters['scope'],
                  ),
                ),
                GoRoute(
                  path: AppRoute.wtmBodyPhoto,
                  name: AppRoute.wtmBodyPhotoName,
                  // WTM Atelier body & try-on manager (Fix 2 + Fix 5) — consent
                  // gate + gallery + studio-model/mannequin picker + body data,
                  // all on the real providers (§10 consent never bypassed).
                  builder: (context, state) => const WtmBodyPhotoScreen(),
                ),
                GoRoute(
                  path: AppRoute.wtmBrandStore,
                  name: AppRoute.wtmBrandStoreName,
                  builder: (context, state) => const BrandStoreStub(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoute.wtmSocial,
                  name: AppRoute.wtmSocialName,
                  // P8: the real community feed (gated on the community flag).
                  builder: (context, state) => const WtmSocialScreen(),
                  routes: [
                    GoRoute(
                      path: 'post',
                      name: AppRoute.wtmPostName,
                      builder: (context, state) {
                        final extra = state.extra;
                        if (extra is! Post) return const WtmSocialScreen();
                        return WtmPostDetailScreen(post: extra);
                      },
                    ),
                    GoRoute(
                      path: 'compose',
                      name: AppRoute.wtmComposeName,
                      // Share Look passes a WtmComposeArgs prefill (outfit /
                      // saved look); a bare push opens the blank composer.
                      builder: (context, state) => WtmComposeScreen(
                        args: state.extra is WtmComposeArgs
                            ? state.extra as WtmComposeArgs
                            : null,
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: AppRoute.wtmUser,
                  name: AppRoute.wtmUserName,
                  // P8: another user's public profile (`?u=<userId>`).
                  builder: (context, state) => WtmPublicProfileScreen(
                    userId: state.uri.queryParameters['u'] ?? '',
                  ),
                  routes: [
                    GoRoute(
                      path: 'followers',
                      name: AppRoute.wtmUserFollowersName,
                      builder: (context, state) => WtmFollowListScreen(
                        mode: WtmFollowListMode.followers,
                        userId: state.uri.queryParameters['u'],
                      ),
                    ),
                    GoRoute(
                      path: 'following',
                      name: AppRoute.wtmUserFollowingName,
                      builder: (context, state) => WtmFollowListScreen(
                        mode: WtmFollowListMode.following,
                        userId: state.uri.queryParameters['u'],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoute.wtmInbox,
                  name: AppRoute.wtmInboxName,
                  // P9: the real Inbox (Activity/Drops/System + deep-links).
                  builder: (context, state) => const WtmInboxScreen(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoute.wtmProfile,
                  name: AppRoute.wtmProfileName,
                  // P7: the real Profile (segments, stats, Style DNA).
                  builder: (context, state) => const WtmProfileScreen(),
                  routes: [
                    GoRoute(
                      path: 'edit',
                      name: AppRoute.wtmProfileEditName,
                      builder: (context, state) =>
                          const WtmProfileEditScreen(),
                    ),
                    GoRoute(
                      path: 'saved',
                      name: AppRoute.wtmProfileSavedName,
                      // P8: the real saved-posts (bookmarks) list.
                      builder: (context, state) => const WtmSavedPostsScreen(),
                    ),
                  ],
                ),
                GoRoute(
                  path: AppRoute.wtmSettings,
                  name: AppRoute.wtmSettingsName,
                  // P7: the real Settings + account lifecycle (Delete Account).
                  builder: (context, state) => const WtmSettingsScreen(),
                ),
              ],
            ),
          ],
        ),
      // Full-bleed WTM flow screens (no nav): generating → result → adjust
      // (§3.4/3.5), the paywall (§3.7), and the auth/onboarding entry (§3.A).
      // Cut over with the shell above — available in every build mode.
      if (_launchWtmShell) ...[
        GoRoute(
          path: AppRoute.wtmSplash,
          name: AppRoute.wtmSplashName,
          builder: (context, state) => const WtmSplashScreen(),
        ),
        GoRoute(
          path: AppRoute.wtmAuth,
          name: AppRoute.wtmAuthName,
          builder: (context, state) => const WtmAuthScreen(),
        ),
        GoRoute(
          path: AppRoute.wtmOnboarding,
          name: AppRoute.wtmOnboardingName,
          builder: (context, state) => const WtmOnboardingScreen(),
        ),
        GoRoute(
          path: AppRoute.wtmMirrorGenerating,
          name: AppRoute.wtmMirrorGeneratingName,
          builder: (context, state) => const WtmMirrorGeneratingScreen(),
        ),
        GoRoute(
          path: AppRoute.wtmMirrorResult,
          name: AppRoute.wtmMirrorResultName,
          builder: (context, state) => const WtmMirrorResultScreen(),
        ),
        GoRoute(
          path: AppRoute.wtmMirrorAdjust,
          name: AppRoute.wtmMirrorAdjustName,
          builder: (context, state) {
            final extra = state.extra;
            if (extra is! WtmAdjustArgs) {
              return const WtmMirrorResultScreen();
            }
            return WtmMirrorAdjustScreen(
              imageUrl: extra.imageUrl,
              initial: extra.initial,
            );
          },
        ),
        GoRoute(
          path: AppRoute.wtmPaywall,
          name: AppRoute.wtmPaywallName,
          // P6: the real membership paywall on the shipped subscription layer.
          builder: (context, state) => const WtmPaywallScreen(),
        ),
        GoRoute(
          path: AppRoute.wtmReferral,
          name: AppRoute.wtmReferralName,
          // Invite friends — referral rewards (§24), full-screen over the shell.
          builder: (context, state) => const WtmReferralScreen(),
        ),
        GoRoute(
          path: AppRoute.wtmNotifPrefs,
          name: AppRoute.wtmNotifPrefsName,
          // Per-category notification (push) preferences (§20).
          builder: (context, state) => const WtmNotificationPrefsScreen(),
        ),
        GoRoute(
          path: AppRoute.wtmGiveawayCreate,
          name: AppRoute.wtmGiveawayCreateName,
          // WTM-styled giveaway create, full-screen over the shell. A /wtm route
          // so it's reachable in WTM_SHELL without the auth gate bouncing it.
          pageBuilder: (context, state) {
            final extra = state.extra;
            return appSharedAxisPage(
              child: CreateGiveawayScreen(
                item: extra is WardrobeItem ? extra : null,
              ),
            );
          },
        ),
        GoRoute(
          path: AppRoute.wtmGiveawayChat,
          name: AppRoute.wtmGiveawayChatName,
          // Secret pickup chat (owner ↔ accepted requester), full-screen over
          // the shell. Reached with `?id=<giveawayId>`.
          pageBuilder: (context, state) => appSharedAxisPage(
            child: WtmGiveawayChatScreen(
              giveawayId: state.uri.queryParameters['id'] ?? '',
            ),
          ),
        ),
      ],
    ],
  );
});
