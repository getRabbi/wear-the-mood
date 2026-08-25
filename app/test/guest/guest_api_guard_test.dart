import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/core/network/auth_interceptor.dart';
import 'package:app/core/network/guest_api_guard.dart';

import '../helpers/fake_dio.dart';

/// THE NETWORK BOUNDARY.
///
/// Hiding buttons proves nothing; this proves the thing that actually matters —
/// that with no session, the only requests that reach the wire are public
/// reads. Every repository in the app shares one Dio, so what passes here is
/// exactly what a guest can cause the app to do.
///
/// The assertions are deliberately about the ADAPTER: `adapter.calls` counts
/// requests that actually left. Zero is zero.
void main() {
  late FakeAdapter adapter;
  late List<String> hits;

  /// A Dio wired exactly like `dioProvider`: the guard first, then the adapter.
  Dio build({required bool hasSession}) {
    hits = [];
    adapter = FakeAdapter((options) {
      hits.add('${options.method} ${options.path}');
      return jsonResponse(const {'ok': true});
    });
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(GuestApiGuard(hasSession: () => hasSession));
    return dio;
  }

  Future<Object?> attempt(Future<void> Function() call) async {
    try {
      await call();
      return null;
    } catch (error) {
      return error;
    }
  }

  group('a guest cannot reach any protected endpoint', () {
    // One entry per line of the "must never work without a real account" list.
    const forbidden = <({String method, String path, String what})>[
      (
        method: 'POST',
        path: '/v1/media/upload-url',
        what: 'upload any image to backend or R2',
      ),
      (
        method: 'POST',
        path: '/v1/wardrobe',
        what: 'create a closet item / start background removal',
      ),
      (
        method: 'POST',
        path: '/v1/wardrobe/local-cutout',
        what: 'create a local-cutout temp job',
      ),
      (method: 'PATCH', path: '/v1/wardrobe/abc', what: 'edit a closet item'),
      (
        method: 'DELETE',
        path: '/v1/wardrobe/abc',
        what: 'delete a closet item',
      ),
      (method: 'POST', path: '/v1/tryon', what: 'create an AI try-on job'),
      (
        method: 'GET',
        path: '/v1/tryon/job-1',
        what: 'read a private generation',
      ),
      (method: 'GET', path: '/v1/tryon/results', what: 'read try-on history'),
      (method: 'POST', path: '/v1/ai-studio/enhance', what: 'run AI Enhance'),
      (
        method: 'POST',
        path: '/v1/ai-studio/catalog-shot',
        what: 'run Catalog Model Shot',
      ),
      (method: 'GET', path: '/v1/credits', what: 'read credits'),
      (method: 'POST', path: '/v1/credits/reserve', what: 'reserve credits'),
      (method: 'GET', path: '/v1/me', what: 'read the account'),
      (method: 'PATCH', path: '/v1/profile', what: 'edit a profile'),
      (method: 'POST', path: '/v1/outfits', what: 'create an outfit'),
      (
        method: 'PUT',
        path: '/v1/discover/saved/p1',
        what: 'save a product to the account',
      ),
      (
        method: 'DELETE',
        path: '/v1/discover/saved/p1',
        what: 'unsave a product',
      ),
      (method: 'GET', path: '/v1/discover/saved', what: 'read saved products'),
      (
        method: 'POST',
        path: '/v1/discover/interactions',
        what: 'write a behavioural signal',
      ),
      (
        method: 'GET',
        path: '/v1/discover/preferences',
        what: 'read shopping preferences',
      ),
      (method: 'POST', path: '/v1/social/posts', what: 'post to the community'),
      (method: 'POST', path: '/v1/social/posts/p1/like', what: 'like a post'),
      (
        method: 'POST',
        path: '/v1/social/posts/p1/comments',
        what: 'comment on a post',
      ),
      (method: 'POST', path: '/v1/social/follow/u1', what: 'follow someone'),
      (method: 'POST', path: '/v1/giveaways', what: 'create a giveaway'),
      (
        method: 'POST',
        path: '/v1/giveaways/bbbbbbbb-cccc-dddd-eeee-ffffffffffff/claim',
        what: 'enter a giveaway',
      ),
      (method: 'GET', path: '/v1/giveaways/mine', what: 'read owned giveaways'),
      (
        method: 'POST',
        path: '/v1/notifications/token',
        what: 'register for push',
      ),
      (
        method: 'GET',
        path: '/v1/notifications',
        what: 'read private notifications',
      ),
      (method: 'POST', path: '/v1/billing/verify', what: 'complete a purchase'),
      (method: 'POST', path: '/v1/consents', what: 'record consent'),
      (method: 'POST', path: '/v1/stylist/suggest', what: 'query the stylist'),
      (
        method: 'POST',
        path: '/v1/style-memory/feedback',
        what: 'write a taste signal',
      ),
      (method: 'DELETE', path: '/v1/account', what: 'delete the account'),
    ];

    for (final route in forbidden) {
      test('${route.method} ${route.path} — ${route.what}', () async {
        final dio = build(hasSession: false);

        final error = await attempt(
          () => dio.request<dynamic>(
            route.path,
            options: Options(method: route.method),
          ),
        );

        // Nothing left the app.
        expect(
          hits,
          isEmpty,
          reason: 'a guest must not be able to ${route.what}',
        );
        // And it failed in a way the app already knows how to present.
        expect(error, isA<DioException>());
        expect((error! as DioException).response?.statusCode, 401);
        expect(
          ((error as DioException).response!.data as Map)['error']['code'],
          'UNAUTHENTICATED',
        );
      });
    }
  });

  group('a guest CAN reach the public reads, rewritten onto the mirror', () {
    const mirrored = <({String method, String from, String to})>[
      (method: 'GET', from: '/v1/flags', to: '/v1/public/flags'),
      (
        method: 'GET',
        from: '/v1/discover/products',
        to: '/v1/public/discover/products',
      ),
      (
        method: 'GET',
        from: '/v1/discover/facets',
        to: '/v1/public/discover/facets',
      ),
      (
        method: 'GET',
        from: '/v1/discover/products/11111111-2222-3333-4444-555555555555',
        to: '/v1/public/discover/products/11111111-2222-3333-4444-555555555555',
      ),
      (
        method: 'GET',
        from:
            '/v1/discover/products/11111111-2222-3333-4444-555555555555/similar',
        to: '/v1/public/discover/products/11111111-2222-3333-4444-555555555555/similar',
      ),
      (
        method: 'POST',
        from:
            '/v1/discover/products/11111111-2222-3333-4444-555555555555/click',
        to: '/v1/public/discover/products/11111111-2222-3333-4444-555555555555/click',
      ),
      (method: 'GET', from: '/v1/news', to: '/v1/public/news'),
      (
        method: 'GET',
        from: '/v1/news/66666666-7777-8888-9999-aaaaaaaaaaaa',
        to: '/v1/public/news/66666666-7777-8888-9999-aaaaaaaaaaaa',
      ),
      (method: 'GET', from: '/v1/giveaways', to: '/v1/public/giveaways'),
      (
        method: 'GET',
        from: '/v1/giveaways/bbbbbbbb-cccc-dddd-eeee-ffffffffffff',
        to: '/v1/public/giveaways/bbbbbbbb-cccc-dddd-eeee-ffffffffffff',
      ),
    ];

    for (final route in mirrored) {
      test('${route.method} ${route.from} → ${route.to}', () async {
        final dio = build(hasSession: false);

        await dio.request<dynamic>(
          route.from,
          options: Options(method: route.method),
        );

        expect(hits, ['${route.method} ${route.to}']);
      });
    }

    test('a query string survives the rewrite', () async {
      final dio = build(hasSession: false);
      await dio.get<dynamic>(
        '/v1/discover/products',
        queryParameters: {'q': 'linen', 'country': 'BD'},
      );

      expect(hits, ['GET /v1/public/discover/products']);
      expect(adapter.lastRequest!.queryParameters, {
        'q': 'linen',
        'country': 'BD',
      });
    });

    test('the wrong METHOD on a public path is still denied', () async {
      // The catalog is readable; writing to it is not, and sharing a path with
      // a mirrored read must not carry a write through with it.
      final dio = build(hasSession: false);
      final error = await attempt(
        () => dio.delete<dynamic>(
          '/v1/news/66666666-7777-8888-9999-aaaaaaaaaaaa',
        ),
      );

      expect(hits, isEmpty);
      expect((error! as DioException).response?.statusCode, 401);
    });

    test('a deeper path under a mirrored prefix is denied', () async {
      // `/v1/news/{id}` is mirrored; `/v1/news/{id}/closet` reads the caller's
      // wardrobe and must not be.
      final dio = build(hasSession: false);
      final error = await attempt(
        () => dio.get<dynamic>(
          '/v1/news/66666666-7777-8888-9999-aaaaaaaaaaaa/closet',
        ),
      );

      expect(hits, isEmpty);
      expect((error! as DioException).response?.statusCode, 401);
    });

    test(
      'an already-public path is passed through, not double-rewritten',
      () async {
        final dio = build(hasSession: false);
        await dio.get<dynamic>('/v1/public/news');

        expect(hits, ['GET /v1/public/news']);
      },
    );
  });

  group('the guard is inert for a signed-in user', () {
    test('a protected write goes straight through, unmodified', () async {
      final dio = build(hasSession: true);
      await dio.post<dynamic>('/v1/tryon');

      expect(hits, ['POST /v1/tryon']);
    });

    test('a public read is NOT rewritten for a member', () async {
      // A member gets the personalized route, with their saved state and
      // ranking. The mirror is for guests only.
      final dio = build(hasSession: true);
      await dio.get<dynamic>('/v1/discover/products');

      expect(hits, ['GET /v1/discover/products']);
    });

    test('every forbidden route above is reachable WITH a session', () async {
      // The other half of the proof: the guard denies because there is no
      // session, not because these endpoints are broken.
      final dio = build(hasSession: true);
      await dio.post<dynamic>('/v1/media/upload-url');
      await dio.post<dynamic>('/v1/wardrobe');
      await dio.get<dynamic>('/v1/credits');

      expect(hits, [
        'POST /v1/media/upload-url',
        'POST /v1/wardrobe',
        'GET /v1/credits',
      ]);
    });
  });

  group('paths outside the API prefix are none of the guard\'s business', () {
    test('a health check is untouched', () async {
      final dio = build(hasSession: false);
      await dio.get<dynamic>('/health');

      expect(hits, ['GET /health']);
    });

    test('an absolute third-party URL is untouched', () async {
      // The presigned R2 PUT is absolute and carries its own authorization.
      final dio = build(hasSession: false);
      await dio.get<dynamic>('https://cdn.example.test/image.jpg');

      expect(hits.single, contains('cdn.example.test'));
    });

    test(
      'an absolute URL pointing AT a protected API path is still denied',
      () async {
        final dio = build(hasSession: false);
        final error = await attempt(
          () => dio.post<dynamic>('https://api.test/v1/tryon'),
        );

        expect(hits, isEmpty);
        expect((error! as DioException).response?.statusCode, 401);
      },
    );
  });

  group('an outage never reads as "please sign in"', () {
    test(
      'a connection failure maps to NETWORK_ERROR, not UNAUTHENTICATED',
      () async {
        // A guest with no internet must be told the network is down. Showing them
        // a sign-in prompt for a dropped connection is the specific mis-diagnosis
        // that turns a two-second retry into an abandoned session.
        final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
          ..httpClientAdapter = _FailingAdapter()
          ..interceptors.add(GuestApiGuard(hasSession: () => false));

        final error = await attempt(() => dio.get<dynamic>('/v1/news'));

        final api = ApiException.fromDio(error! as DioException);
        expect(api.code, ApiErrorCode.network);
        expect(api.code, isNot(ApiErrorCode.unauthenticated));
      },
    );

    test("the guard's own refusal maps to UNAUTHENTICATED", () async {
      final dio = build(hasSession: false);
      final error = await attempt(() => dio.post<dynamic>('/v1/tryon'));

      final api = ApiException.fromDio(error! as DioException);
      expect(api.code, ApiErrorCode.unauthenticated);
      // And it carries no raw backend text — the UI shows localized copy chosen
      // by the action, never this string.
      expect(api.message, isNot(contains('Exception')));
      expect(api.message, isNot(contains('DioException')));
    });
  });

  group('a denial does not wake the auth-refresh machinery', () {
    test('the following error interceptors never see the rejection', () async {
      // `AuthInterceptor` treats any 401 as a recoverable session problem and
      // responds by refreshing and, failing that, signing the user out. For a
      // guest there is no session to refresh, so letting it run would mean a
      // real Supabase round trip and a sign-out call on EVERY denied request.
      var refreshAttempts = 0;
      var signOuts = 0;

      hits = [];
      final adapter = FakeAdapter((options) {
        hits.add('${options.method} ${options.path}');
        return jsonResponse(const {'ok': true});
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = adapter
        ..interceptors.add(GuestApiGuard(hasSession: () => false))
        ..interceptors.add(
          AuthInterceptor(
            dio: Dio(),
            accessToken: () => null,
            refreshToken: () async {
              refreshAttempts++;
              return null;
            },
            onAuthFailure: () async => signOuts++,
          ),
        );

      final error = await attempt(() => dio.post<dynamic>('/v1/tryon'));

      expect(hits, isEmpty);
      expect((error! as DioException).response?.statusCode, 401);
      expect(refreshAttempts, 0, reason: 'nothing to refresh for a guest');
      expect(signOuts, 0, reason: 'a guest cannot be signed out');
    });
  });

  group('publicPathFor', () {
    test('answers null for anything not mirrored', () {
      expect(GuestApiGuard.publicPathFor('GET', '/v1/credits'), isNull);
      expect(GuestApiGuard.publicPathFor('POST', '/v1/tryon'), isNull);
      expect(GuestApiGuard.publicPathFor('GET', '/v1/whatever'), isNull);
    });

    test('is case-insensitive about the method', () {
      expect(GuestApiGuard.publicPathFor('get', '/v1/news'), '/v1/public/news');
    });

    test('rewrites only the leading /v1/ segment', () {
      expect(
        GuestApiGuard.publicPathFor('GET', '/v1/discover/products'),
        '/v1/public/discover/products',
      );
    });
  });
}

/// An adapter that fails the way a dead connection does.
class _FailingAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'no internet',
    );
  }
}
