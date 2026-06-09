import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_screen.dart';
import '../../features/onboarding/root_gate.dart';
import '../../features/profile/profile_screen.dart';
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
    ],
  );
});
