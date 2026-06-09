import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/home_screen.dart';
import '../../features/tryon/tryon_screen.dart';
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
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoute.tryon,
        name: AppRoute.tryonName,
        builder: (context, state) => const TryOnScreen(),
      ),
    ],
  );
});
