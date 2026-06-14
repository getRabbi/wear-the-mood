import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_screen.dart';
import '../../features/auth/set_password_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/challenges/challenge_detail_screen.dart';
import '../../features/challenges/challenges_screen.dart';
import '../../features/news/news_screen.dart';
import '../../features/onboarding/root_gate.dart';
import '../../features/outfits/create_outfit_screen.dart';
import '../../features/packing/packing_screen.dart';
import '../../features/profile/account_details_screen.dart';
import '../../features/profile/avatar_screen.dart';
import '../../features/wardrobe/add_wardrobe_item_screen.dart';
import '../../features/wardrobe/wardrobe_insights_screen.dart';
import '../../features/outfits/outfits_screen.dart';
import '../../features/paywall/paywall_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/referral/referral_screen.dart';
import '../../features/social/compose_post_screen.dart';
import '../../features/stylist/stylist_screen.dart';
import '../../features/tryon/tryon_history_screen.dart';
import '../../features/tryon/tryon_screen.dart';
import '../../features/wardrobe/wardrobe_screen.dart';
import 'routes.dart';

/// App router, exposed via Riverpod so it can later react to auth state
/// (redirects) and stays testable. Deep links work out of the box from this
/// declarative route table.
final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoute.home,
    debugLogDiagnostics: true,
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
        builder: (context, state) => const TryOnHistoryScreen(),
      ),
      GoRoute(
        path: AppRoute.wardrobe,
        name: AppRoute.wardrobeName,
        builder: (context, state) => const WardrobeScreen(),
        routes: [
          GoRoute(
            path: 'add',
            name: AppRoute.wardrobeAddName,
            builder: (context, state) => const AddWardrobeItemScreen(),
          ),
          GoRoute(
            path: 'insights',
            name: AppRoute.wardrobeInsightsName,
            builder: (context, state) => const WardrobeInsightsScreen(),
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
          );
        },
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
        builder: (context, state) => const NewsScreen(),
      ),
      GoRoute(
        path: AppRoute.referrals,
        name: AppRoute.referralsName,
        builder: (context, state) => const ReferralScreen(),
      ),
      GoRoute(
        path: AppRoute.packing,
        name: AppRoute.packingName,
        builder: (context, state) => const PackingScreen(),
      ),
      GoRoute(
        path: AppRoute.calendar,
        name: AppRoute.calendarName,
        builder: (context, state) => const CalendarScreen(),
      ),
      GoRoute(
        path: AppRoute.outfits,
        name: AppRoute.outfitsName,
        builder: (context, state) => const OutfitsScreen(),
        routes: [
          GoRoute(
            path: 'create',
            name: AppRoute.outfitsCreateName,
            builder: (context, state) => const CreateOutfitScreen(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoute.auth,
        name: AppRoute.authName,
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: AppRoute.setPassword,
        name: AppRoute.setPasswordName,
        builder: (context, state) => const SetPasswordScreen(),
      ),
      GoRoute(
        path: AppRoute.profile,
        name: AppRoute.profileName,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoute.avatar,
        name: AppRoute.avatarName,
        builder: (context, state) => const AvatarScreen(),
      ),
      GoRoute(
        path: AppRoute.accountDetails,
        name: AppRoute.accountDetailsName,
        builder: (context, state) => const AccountDetailsScreen(),
      ),
      GoRoute(
        path: AppRoute.paywall,
        name: AppRoute.paywallName,
        builder: (context, state) => const PaywallScreen(),
      ),
    ],
  );
});
