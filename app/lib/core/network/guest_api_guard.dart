import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// The NETWORK layer of the guest gate, and the one that makes the guarantee
/// provable rather than asserted.
///
/// Hiding buttons stops the taps you thought of. This stops the ones you did
/// not: a stale controller resuming after sign-out, a retry queued before the
/// session died, a deep link that slipped past the router, a future screen
/// whose author never read this file. Every repository in the app shares one
/// [Dio] (`dio_client.dart`), so a single interceptor there is a single choke
/// point for **every** upload, AI job, credit movement and protected write.
///
/// Two rules, in order:
///
/// 1. **A request with a session passes untouched.** This interceptor is inert
///    for signed-in users — Android included, where nothing about it is ever
///    reachable because guest state cannot exist there.
/// 2. **A request without a session is DENIED**, unless its method and path
///    appear in [publicMirrors], in which case it is rewritten onto the public
///    read endpoint that serves the same data with no account attached.
///
/// Deny-by-default is the point: a new endpoint is closed to guests until
/// somebody adds it to the mirror list on purpose.
///
/// The R2 upload path deserves a note, because it looks like a hole and is not:
/// bytes go straight to R2 over a bare [Dio] with no interceptors, but that URL
/// only exists after `POST /v1/media/upload-url` returns a presigned PUT — and
/// that call comes through here. Block the signature and no byte can move.
class GuestApiGuard extends Interceptor {
  GuestApiGuard({required this.hasSession});

  /// Whether a real authenticated session exists right now. A callback rather
  /// than a provider read so this stays a plain unit-testable class.
  final bool Function() hasSession;

  /// The API prefix this guard polices. Anything outside it (health checks,
  /// the referral redirect) is none of its business.
  static const apiPrefix = '/v1/';

  /// Where a guest-safe read is redirected to.
  static const publicPrefix = '/v1/public/';

  /// A resource id, as a UUID and nothing else.
  ///
  /// Deliberately not `[^/]+`. That looser form matched `/v1/giveaways/mine`
  /// and `/v1/giveaways/requested` — two PRIVATE routes that happen to sit
  /// where an id goes — and would have mirrored a request for "the listings I
  /// own" onto the public endpoint. Every id these routes take is a UUID
  /// server-side (the handlers validate it and 404 otherwise), so matching the
  /// real shape costs nothing and closes the whole family of word-shaped
  /// sub-routes, including ones added later.
  static const _uuid =
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';

  /// The complete public read surface, as `METHOD` + a path pattern anchored at
  /// both ends. Each entry mirrors a route that exists on the backend under
  /// [publicPrefix] and returns the same response shape with every per-user
  /// field (saved state, personalization, ownership) omitted.
  ///
  /// Everything here is a READ except the affiliate click, which is a POST only
  /// because that is the shape the shipped client already speaks; its public
  /// counterpart writes nothing and returns one validated destination URL.
  static final List<({String method, RegExp path})> publicMirrors = [
    // Feature flags. Global configuration, identical for every caller — a guest
    // needs them or every flag reads OFF and Discover never appears.
    (method: 'GET', path: RegExp(r'^/v1/flags$')),

    // Shop / Discover catalog: list, filter, facets, detail, similar.
    (method: 'GET', path: RegExp(r'^/v1/discover/products$')),
    (method: 'GET', path: RegExp(r'^/v1/discover/facets$')),
    (method: 'GET', path: RegExp('^/v1/discover/products/$_uuid\$')),
    (method: 'GET', path: RegExp('^/v1/discover/products/$_uuid/similar\$')),

    // "Shop Now". Resolves the merchant destination; records no click, spends
    // nothing, and is rate-limited by IP on the server.
    (method: 'POST', path: RegExp('^/v1/discover/products/$_uuid/click\$')),

    // Newsroom: list + one story. Already per-user-free on the private route.
    (method: 'GET', path: RegExp(r'^/v1/news$')),
    (method: 'GET', path: RegExp('^/v1/news/$_uuid\$')),

    // Giveaways: public listing + public rules. Entering is NOT here, and
    // neither are `/mine` or `/requested` — see [_uuid].
    (method: 'GET', path: RegExp(r'^/v1/giveaways$')),
    (method: 'GET', path: RegExp('^/v1/giveaways/$_uuid\$')),
  ];

  /// The public mirror for [method] [path], or null when there is none (i.e.
  /// the request must be denied for a guest).
  @visibleForTesting
  static String? publicPathFor(String method, String path) {
    final upper = method.toUpperCase();
    for (final rule in publicMirrors) {
      if (rule.method == upper && rule.path.hasMatch(path)) {
        return path.replaceFirst(apiPrefix, publicPrefix);
      }
    }
    return null;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (hasSession()) {
      handler.next(options);
      return;
    }

    final path = _normalize(options.path);
    if (!path.startsWith(apiPrefix)) {
      // Not ours to police (health, absolute third-party URLs).
      handler.next(options);
      return;
    }
    // Already a public path — let it through rather than double-rewriting.
    if (path.startsWith(publicPrefix)) {
      handler.next(options);
      return;
    }

    final mirrored = publicPathFor(options.method, path);
    if (mirrored != null) {
      handler.next(options.copyWith(path: mirrored));
      return;
    }

    // Denied. Rejected as a DioException so it travels the same error path every
    // repository already handles (and `ApiException.fromDio` already maps), with
    // a 401 so nothing mistakes it for a server fault or a network outage.
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        error: 'guest_denied',
        message: 'This action requires an account.',
        response: Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 401,
          data: const {
            'error': {
              'code': 'UNAUTHENTICATED',
              'message': 'This action requires an account.',
            },
          },
        ),
      ),
      // `false` — do NOT hand this to the following error interceptors.
      //
      // Read the flag name carefully: it is `callFollowingErrorInterceptor`, so
      // `true` would run them. Running them is exactly wrong here. AuthInterceptor
      // treats any 401 as a recoverable session problem: it would fire a real
      // Supabase `refreshSession()` for a guest who has no session to refresh,
      // get nothing back, conclude the session is dead, and call `signOut()` —
      // a network round trip and a sign-out on every single denied request.
      false,
    );
  }

  /// Repositories pass relative paths (`/v1/news`); a few pass absolutes. Reduce
  /// both to the path so one set of rules covers them.
  static String _normalize(String path) {
    if (!path.startsWith('http')) return path;
    return Uri.tryParse(path)?.path ?? path;
  }
}
