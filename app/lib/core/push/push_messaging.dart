import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/push_repository.dart';
import '../auth/auth_providers.dart';
import '../router/app_router.dart';

/// OS-level notification permission state, so the preferences screen can show an
/// accurate master status and the right action (§20).
/// - [granted]       the OS lets us deliver push.
/// - [denied]        the user blocked it in system settings (needs Open settings).
/// - [notDetermined] never asked — a contextual prompt is still allowed.
/// - [unavailable]   Firebase isn't configured (tests / key-less dev).
enum PushPermissionStatus { granted, denied, notDetermined, unavailable }

/// Background/terminated message handler (must be a top-level function, §20).
/// FCM auto-displays notification payloads; we just ensure Firebase is ready.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// A push `route` payload is only followed when it is an in-app absolute path
/// (e.g. `/community/post/123`) — never a full URL or custom scheme, so a
/// malformed/hostile payload can't steer the router anywhere unexpected.
bool isValidPushRoute(String route) =>
    route.startsWith('/') && !route.startsWith('//') && !route.contains('://');

/// Daily-stylist push wiring (CLAUDE.md §20): request permission, register the
/// device token to the backend for the signed-in user, and deep-link to the
/// route a tapped notification carries. No-ops until Firebase is initialized
/// (so tests + key-less runs are unaffected).
class PushMessaging {
  PushMessaging(this._ref);

  final Ref _ref;
  bool _started = false;

  /// Native channel to open the OS app-notification settings (Android intent /
  /// iOS Settings). Registered in MainActivity; a no-op elsewhere.
  static const _settingsChannel = MethodChannel('com.fashionos.app/notif_settings');

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

  /// Current OS notification-permission state, WITHOUT prompting — reading it
  /// never shows a dialog, so the preferences screen can render an accurate
  /// master status on open (§20).
  Future<PushPermissionStatus> permissionStatus() async {
    if (Firebase.apps.isEmpty) return PushPermissionStatus.unavailable;
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      return switch (settings.authorizationStatus) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => PushPermissionStatus.granted,
        AuthorizationStatus.denied => PushPermissionStatus.denied,
        AuthorizationStatus.notDetermined => PushPermissionStatus.notDetermined,
      };
    } catch (error) {
      debugPrint('push permission read failed: $error');
      return PushPermissionStatus.unavailable;
    }
  }

  /// Open the OS app-notification settings so a user who denied permission can
  /// re-enable it (there is no in-app way to flip a denied OS toggle).
  Future<void> openSystemNotificationSettings() async {
    try {
      await _settingsChannel.invokeMethod<void>('open');
    } catch (error) {
      debugPrint('open notification settings failed: $error');
    }
  }

  Future<void> _registerCurrent() async {
    // The token endpoint needs an authenticated user.
    if (_ref.read(authRepositoryProvider).currentUser == null) return;
    try {
      final messaging = FirebaseMessaging.instance;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // On iOS getToken() throws until an APNs token exists (fresh install,
        // simulator, or permission never granted). Bail quietly — the
        // onTokenRefresh stream re-registers once APNs comes through.
        final apnsToken = await messaging.getAPNSToken();
        if (apnsToken == null) return;
      }
      final token = await messaging.getToken();
      if (token != null) await _register(token);
    } catch (error) {
      debugPrint('push token fetch failed: $error');
    }
  }

  Future<void> _register(String token) async {
    try {
      await _ref
          .read(pushRepositoryProvider)
          .registerToken(
            token,
            platform: defaultTargetPlatform == TargetPlatform.iOS
                ? 'ios'
                : 'android',
          );
    } catch (error) {
      debugPrint('push token registration failed: $error');
    }
  }

  /// Best-effort: unlink this device's token from the signed-in account.
  /// Call BEFORE signing out — the endpoint needs the user's JWT. Safe no-op
  /// when Firebase isn't configured.
  Future<void> unregister() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _ref.read(pushRepositoryProvider).deleteToken(token);
      }
    } catch (error) {
      debugPrint('push token unregister failed: $error');
    }
  }

  void _openRoute(RemoteMessage message) {
    final route = message.data['route'];
    // Only in-app absolute routes — never let a push payload point the router
    // at schemes/hosts (the auth-gate redirect still applies on top of this).
    if (route is String && isValidPushRoute(route)) {
      _ref.read(goRouterProvider).go(route);
    }
  }
}

final pushMessagingProvider = Provider<PushMessaging>(
  (ref) => PushMessaging(ref),
);
