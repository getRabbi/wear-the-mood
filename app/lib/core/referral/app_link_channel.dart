import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Extract the referral CODE from an `https://wearthemood.com/r/<code>` App Link
/// (or null for anything else). HTTPS + our host + `/r/` path only — mirrors the
/// native intent-filter so a hostile URL can't be treated as a referral.
String? referralCodeFromLink(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return null;
  if (uri.host != 'wearthemood.com' && uri.host != 'www.wearthemood.com') {
    return null;
  }
  final segs = uri.pathSegments;
  if (segs.length >= 2 && segs.first == 'r') {
    final code = segs[1].trim().toUpperCase();
    return code.isEmpty ? null : code;
  }
  return null;
}

/// Wrapper over the native `wtm/app_links` MethodChannel: the launch App Link
/// ([initialCode]) plus a stream of warm links opened while running ([codes]).
class AppLinkChannel {
  AppLinkChannel() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        final code = referralCodeFromLink(call.arguments as String?);
        if (code != null && !_controller.isClosed) _controller.add(code);
      }
    });
  }

  static const _channel = MethodChannel('wtm/app_links');
  final _controller = StreamController<String>.broadcast();

  /// Referral codes from warm App Links (app already running).
  Stream<String> get codes => _controller.stream;

  /// The referral code the app was cold-launched with, if any.
  Future<String?> initialCode() async {
    try {
      final url = await _channel.invokeMethod<String>('getInitialLink');
      return referralCodeFromLink(url);
    } catch (_) {
      return null;
    }
  }
}

final appLinkChannelProvider = Provider<AppLinkChannel>((ref) => AppLinkChannel());
