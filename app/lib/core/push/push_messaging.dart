import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/push_repository.dart';
import '../auth/auth_providers.dart';
import '../router/app_router.dart';

/// Background/terminated message handler (must be a top-level function, §20).
/// FCM auto-displays notification payloads; we just ensure Firebase is ready.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// Daily-stylist push wiring (CLAUDE.md §20): request permission, register the
/// device token to the backend for the signed-in user, and deep-link to the
/// route a tapped notification carries. No-ops until Firebase is initialized
/// (so tests + key-less runs are unaffected).
class PushMessaging {
  PushMessaging(this._ref);

  final Ref _ref;
  bool _started = false;

  Future<void> start() async {
    if (_started || Firebase.apps.isEmpty) return; // not initialized (tests)
    _started = true;
    final messaging = FirebaseMessaging.instance;

    // NOTE: we deliberately do NOT request notification permission here. On a
    // cold launch that's a bad time (CLAUDE.md §20); the prompt is requested
    // contextually via [promptPermission] (e.g. when the user opens the
    // Notifications screen). Token registration is silent and works regardless.

    // Deep-link from a tapped notification (cold start + while backgrounded).
    final initial = await messaging.getInitialMessage();
    if (initial != null) _openRoute(initial);
    FirebaseMessaging.onMessageOpenedApp.listen(_openRoute);

    // Keep the backend's token current: on refresh, and when the user signs in.
    messaging.onTokenRefresh.listen(_register);
    _ref.read(authRepositoryProvider).authStateChanges().listen((_) {
      _registerCurrent();
    });
    await _registerCurrent();
  }

  /// Request the OS notification permission at a contextual moment (Android 13+
  /// POST_NOTIFICATIONS / iOS prompt), then refresh the registered token. Safe
  /// no-op when Firebase isn't configured (tests / key-less dev). Calling it
  /// repeatedly is safe — the OS only shows the dialog once.
  Future<void> promptPermission() async {
    if (Firebase.apps.isEmpty) return;
    await FirebaseMessaging.instance.requestPermission();
    await _registerCurrent();
  }

  Future<void> _registerCurrent() async {
    // The token endpoint needs an authenticated user.
    if (_ref.read(authRepositoryProvider).currentUser == null) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _register(token);
  }

  Future<void> _register(String token) async {
    try {
      await _ref.read(pushRepositoryProvider).registerToken(token);
    } catch (error) {
      debugPrint('push token registration failed: $error');
    }
  }

  void _openRoute(RemoteMessage message) {
    final route = message.data['route'];
    if (route is String && route.isNotEmpty) {
      _ref.read(goRouterProvider).go(route);
    }
  }
}

final pushMessagingProvider = Provider<PushMessaging>((ref) => PushMessaging(ref));
