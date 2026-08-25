import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'protected_action.dart';

/// What a guest was trying to do when they were stopped.
///
/// Deliberately almost empty. It holds a semantic action and, at most, a PUBLIC
/// resource id (a product id, a giveaway id) — the kind of value that already
/// travels in a shareable link.
///
/// It never holds, and must never grow: a selected photo or its path, a draft,
/// a comment body, an upload, an access token, a credit amount, or anything
/// that would let sign-in silently complete an action the user has not
/// re-confirmed. Queueing a photo before authentication would mean a photo
/// exists on disk, attached to an intent, belonging to nobody — exactly the
/// situation Guest Mode exists to prevent.
@immutable
class PendingAuthIntent {
  const PendingAuthIntent({required this.action, this.resourceId});

  final ProtectedAction action;

  /// A public identifier, or null. Capped at [_maxResourceIdLength] on read so
  /// a corrupt or hostile value cannot become an unbounded string.
  final String? resourceId;

  static const _maxResourceIdLength = 128;

  Map<String, Object?> toJson() => {
    'action': action.name,
    if (resourceId != null) 'id': resourceId,
  };

  /// Returns null for anything unrecognised — an action name from a newer
  /// build, a truncated write, hand-edited storage. A stale intent must be
  /// dropped, never guessed at.
  static PendingAuthIntent? fromJson(Map<String, Object?> json) {
    final name = json['action'];
    if (name is! String) return null;
    final action = ProtectedAction.values
        .where((a) => a.name == name)
        .firstOrNull;
    if (action == null) return null;
    final id = json['id'];
    final resourceId =
        id is String && id.isNotEmpty && id.length <= _maxResourceIdLength
        ? id
        : null;
    // An intent that NEEDS an id but has none cannot be resumed anywhere
    // sensible, so it is not worth keeping.
    if (action.resumeNeedsResourceId && resourceId == null) return null;
    return PendingAuthIntent(action: action, resourceId: resourceId);
  }

  @override
  bool operator ==(Object other) =>
      other is PendingAuthIntent &&
      other.action == action &&
      other.resourceId == resourceId;

  @override
  int get hashCode => Object.hash(action, resourceId);

  @override
  String toString() =>
      'PendingAuthIntent(${action.analyticsName}, id: ${resourceId ?? '-'})';
}

/// Holds the one intent awaiting authentication.
///
/// Persisted (in `shared_preferences`, the app's store for non-sensitive local
/// state) rather than kept in memory, because iOS can background — and in a
/// low-memory moment terminate — the app during a browser-based OAuth round
/// trip. An intent lost there means the user signs in and lands nowhere near
/// what they asked for.
///
/// **Resume is once.** [take] reads and clears in the same call, so a rebuild,
/// a second listener or a double-fired auth event cannot resume the same intent
/// twice — which is what keeps a resumed Save from saving twice and a resumed
/// giveaway entry from entering twice.
class PendingAuthIntentController extends Notifier<PendingAuthIntent?> {
  static const storageKey = 'wtm.guest.v1.pending_intent';

  @override
  PendingAuthIntent? build() {
    unawaited(restore());
    return null;
  }

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (error) {
      // No platform channel (unit tests) or unwritable disk. The in-memory
      // value still works for the current session.
      debugPrint('pending intent storage unavailable: $error');
      return null;
    }
  }

  /// Reload a persisted intent (e.g. after the app was killed mid-OAuth).
  Future<void> restore() async {
    final prefs = await _prefs();
    final raw = prefs?.getString(storageKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await clear();
        return;
      }
      final intent = PendingAuthIntent.fromJson(
        decoded.cast<String, Object?>(),
      );
      if (intent == null) {
        await clear();
        return;
      }
      // A real session that arrived first wins; never resurrect an intent over
      // a live one already set this session.
      state ??= intent;
    } catch (error) {
      debugPrint('pending intent decode failed: $error');
      await clear();
    }
  }

  /// Records [intent], replacing any earlier one — the most recent thing the
  /// user asked for is the thing to resume.
  Future<void> set(PendingAuthIntent intent) async {
    state = intent;
    final prefs = await _prefs();
    try {
      await prefs?.setString(storageKey, jsonEncode(intent.toJson()));
    } catch (error) {
      debugPrint('pending intent write failed: $error');
    }
  }

  /// Reads and clears atomically. Returns null when there is nothing pending —
  /// so calling it twice resumes once.
  Future<PendingAuthIntent?> take() async {
    final current = state;
    if (current == null) return null;
    state = null;
    await _erase();
    return current;
  }

  /// Drops any pending intent — on cancellation, sign-out, account deletion, an
  /// invalid resource, or an unrecoverable failure.
  Future<void> clear() async {
    state = null;
    await _erase();
  }

  Future<void> _erase() async {
    final prefs = await _prefs();
    try {
      await prefs?.remove(storageKey);
    } catch (error) {
      debugPrint('pending intent clear failed: $error');
    }
  }
}

final pendingAuthIntentProvider =
    NotifierProvider<PendingAuthIntentController, PendingAuthIntent?>(
      PendingAuthIntentController.new,
    );
