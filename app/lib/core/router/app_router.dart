import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_screen.dart';
import '../../features/onboarding/root_gate.dart';
import '../../features/outfits/create_outfit_screen.dart';
import '../../features/profile/avatar_screen.dart';
import '../../features/wardrobe/add_wardrobe_item_screen.dart';
import '../../features/outfits/outfits_screen.dart';
import '../../features/paywall/paywall_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/social/compose_post_screen.dart';
import '../../features/stylist/stylist_screen.dart';
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
        path: AppRoute.wardrobe,
        name: AppRoute.wardrobeName,
        builder: (context, state) => const WardrobeScreen(),
        routes: [
          GoRoute(
            path: 'add',
            name: AppRoute.wardrobeAddName,
            builder: (context, state) => const AddWardrobeItemScreen(),
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
        builder: (context, state) => const ComposePostScreen(),
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
        path: AppRoute.paywall,
        name: AppRoute.paywallName,
        builder: (context, state) => const PaywallScreen(),
      ),
    ],
  );
});
