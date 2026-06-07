import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';

void main() {
  test('goRouterProvider provides a GoRouter starting at home', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = container.read(goRouterProvider);

    expect(router, isA<GoRouter>());
    expect(
      router.routeInformationProvider.value.uri.path,
      AppRoute.home,
    );
  });
}
