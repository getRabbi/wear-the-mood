import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/wardrobe_analytics.dart';
import '../../data/models/wardrobe_gap.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/ai_studio_repository.dart';
import '../../data/repositories/wardrobe_repository.dart';
import '../../shared/utils/uuid.dart';
import 'drawers/drawer_store.dart';
import 'wardrobe_image_service.dart';

/// Surfaces a background-add failure (upload / create / enhance) to the closet
/// screen, which shows a snackbar. Cleared after it's shown.
class WardrobeAddError extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? message) => state = message;
}

final wardrobeAddErrorProvider = NotifierProvider<WardrobeAddError, String?>(
  WardrobeAddError.new,
);

/// Cost-per-wear + ROI insights (§24). Auto-disposes so it refreshes on reopen;
/// invalidate after a wear is logged.
final wardrobeAnalyticsProvider = FutureProvider.autoDispose<WardrobeAnalytics>(
  (ref) {
    return ref.watch(wardrobeRepositoryProvider).getAnalytics();
  },
);

/// Closet-gap analysis — missing essentials, shoppable (§24).
final wardrobeGapsProvider = FutureProvider.autoDispose<List<WardrobeGap>>((
  ref,
) {
  return ref.watch(wardrobeRepositoryProvider).getGaps();
});

/// The full closet (`GET /v1/wardrobe`) with robust live polling for in-progress
/// cutouts (§2.2). A freshly added item lands as `queued`/`processing`; the
/// background-removal worker flips it to `done` server-side. While ANY item is
/// processing this:
///  - re-fetches every [_pollInterval] via a single [Timer.periodic] (not a
///    fragile self-invalidating one-shot chain),
///  - holds a keep-alive so a route/tab transition can't kill the poll
///    mid-flight (released when nothing is processing, so it still auto-disposes
///    when idle),
///  - tolerates transient fetch errors (the next tick retries; it backs off only
///    after [_maxErrorStreak] consecutive failures),
///  - hard-stops after [_maxPollDuration] so it can NEVER poll forever.
/// `done` is only ever taken from the server row — the client never marks it done
/// locally. The card's scrim has its own failsafe + pull-to-refresh remain.
///
/// Poll cadence for in-progress cutouts — a provider so tests can override it to
/// a tiny duration (the runtime default is every 4s).
final wardrobeCutoutPollIntervalProvider = Provider<Duration>(
  (_) => const Duration(seconds: 2),
);

class WardrobeItemsNotifier extends AsyncNotifier<List<WardrobeItem>> {
  static const _maxPollDuration = Duration(minutes: 3);
  static const _maxErrorStreak = 4;

  Duration _pollInterval = const Duration(seconds: 2);
  Timer? _poll;
  void Function()? _releaseKeepAlive; // KeepAliveLink.close (type not exported)
  DateTime? _processingSince;
  int _errorStreak = 0;

  @override
  Future<List<WardrobeItem>> build() async {
    _pollInterval = ref.read(wardrobeCutoutPollIntervalProvider);
    ref.onDispose(_teardown);
    final items = await ref.watch(wardrobeRepositoryProvider).getItems();
    _arm(items);
    return items;
  }

  void _teardown() {
    _poll?.cancel();
    _poll = null;
    _releaseKeepAlive?.call();
    _releaseKeepAlive = null;
  }

  /// (Re)arm polling from the latest items. Polls while a cutout is being
  /// generated OR an AI Enhance is running, so the enhanced cover appears on its
  /// own (~within one poll of completion) without a manual refresh / tab switch.
  void _arm(List<WardrobeItem> items) {
    if (!items.any((i) => i.isProcessingCutout || i.isEnhancing)) {
      _teardown();
      _processingSince = null;
      _errorStreak = 0;
      return;
    }
    _processingSince ??= DateTime.now();
    // Failsafe: never poll forever (a stuck/forgotten backend job, a flaky
    // connection). Stop the timer + release the keep-alive; the card's scrim
    // failsafe and pull-to-refresh let the user recover.
    if (DateTime.now().difference(_processingSince!) > _maxPollDuration) {
      _poll?.cancel();
      _poll = null;
      _releaseKeepAlive?.call();
      _releaseKeepAlive = null;
      return;
    }
    _releaseKeepAlive ??= ref.keepAlive().close; // survive transitions while processing
    _poll ??= Timer.periodic(_pollInterval, (_) => _tick());
  }

  Future<void> _tick() async {
    try {
      final server = await ref.read(wardrobeRepositoryProvider).getItems();
      _errorStreak = 0;
      _apply(_mergeWithLocal(server));
    } catch (_) {
      _errorStreak++;
      if (_errorStreak >= _maxErrorStreak) {
        _poll?.cancel();
        _poll = null; // stop hammering; keep the last good grid + failsafes
        _releaseKeepAlive?.call();
        _releaseKeepAlive = null;
      }
      // transient: the periodic timer retries on the next tick.
    }
  }

  /// Fold a fresh server list into the current one, PRESERVING optimistic state
  /// so the grid never flashes:
  ///  - pending uploads (temp rows not yet on the server) stay at the front,
  ///  - a just-added row keeps its local preview bytes until its real
  ///    background-removed image is ready, so the tile doesn't blink to a
  ///    network fetch and back.
  List<WardrobeItem> _mergeWithLocal(List<WardrobeItem> server) {
    final current = state.asData?.value ?? const <WardrobeItem>[];
    final pending = [for (final i in current) if (i.isUploading) i];
    final localById = <String, Uint8List>{
      for (final i in current)
        if (i.localBytes != null && !i.isUploading) i.id: i.localBytes!,
    };
    final serverIds = {for (final s in server) s.id};
    return [
      for (final p in pending)
        if (!serverIds.contains(p.id)) p,
      for (final s in server)
        (localById[s.id] != null && s.processedImageUrl == null)
            ? s.copyWith(localBytes: localById[s.id])
            : s,
    ];
  }

  /// Commit a new list, but ONLY rebuild the grid when something a tile shows
  /// actually changed — an unchanged 2s poll must not churn the UI (that reran
  /// the entrance animation / reloaded images = flicker).
  void _apply(List<WardrobeItem> items) {
    final current = state.asData?.value;
    if (current == null || !_sameGrid(current, items)) {
      state = AsyncData(items);
    }
    _arm(items);
  }

  static bool _sameGrid(List<WardrobeItem> a, List<WardrobeItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.id != y.id ||
          x.imageUrl != y.imageUrl ||
          x.processedImageUrl != y.processedImageUrl ||
          x.cutoutStatus != y.cutoutStatus ||
          x.aiStatus != y.aiStatus ||
          x.title != y.title ||
          (x.localBytes == null) != (y.localBytes == null)) {
        return false;
      }
    }
    return true;
  }

  /// Force a fresh fetch NOW (pull-to-refresh / app resume); resumes polling if
  /// items are still processing. Resets the failsafe window + error streak.
  Future<void> refresh() async {
    _processingSince = null;
    _errorStreak = 0;
    final next = await AsyncValue.guard(
      () => ref.read(wardrobeRepositoryProvider).getItems(),
    );
    state = next;
    final items = next.asData?.value;
    if (items != null) _arm(items);
  }

  /// INSTANT, robust add. Shows the picked photo in the closet immediately (from
  /// local bytes) and runs the upload + create + optional AI enhance entirely in
  /// the background, then reconciles with the real server row. The user never
  /// waits on the network to see their piece; a failure is surfaced via
  /// [wardrobeAddErrorProvider] and the optimistic tile is removed.
  Future<void> startBackgroundAdd({
    required Uint8List bytes,
    String? title,
    String? category,
    String? drawerId,
    bool enhance = false,
  }) async {
    final tempId = 'pending-${uuidV4()}';
    _insertFront(
      WardrobeItem(
        id: tempId,
        title: title,
        category: category,
        localBytes: bytes,
        cutoutStatus: 'queued',
        aiStatus: enhance ? 'queued' : null,
      ),
    );
    try {
      final media = await ref.read(wardrobeImageServiceProvider).upload(bytes);
      final item = await ref
          .read(wardrobeRepositoryProvider)
          .addItem(
            title: title,
            category: category,
            imageUrl: media.legacyUrl,
            objectKey: media.objectKey,
          );
      if (drawerId != null) {
        ref.read(closetAssignmentsProvider.notifier).assign(item.id, drawerId);
      }
      // Swap the temp row for the real one, KEEPING the local preview so the tile
      // holds steady until the background-removed image is ready.
      _reconcile(
        tempId,
        item.copyWith(
          localBytes: bytes,
          aiStatus: enhance ? 'queued' : item.aiStatus,
        ),
      );
      if (enhance) {
        await ref.read(aiStudioRepositoryProvider).enhanceItem(item.id);
        ref.read(analyticsProvider).track(AnalyticsEvents.aiEnhanceStarted);
      }
    } on ApiException catch (e) {
      _removePending(tempId);
      ref.read(wardrobeAddErrorProvider.notifier).set(e.message);
    } catch (_) {
      _removePending(tempId);
      ref
          .read(wardrobeAddErrorProvider.notifier)
          .set('Could not add that. Please try again.');
    }
  }

  void _insertFront(WardrobeItem item) {
    final current = state.asData?.value ?? const <WardrobeItem>[];
    state = AsyncData([item, for (final i in current) if (i.id != item.id) i]);
    _arm(state.requireValue);
  }

  void _reconcile(String tempId, WardrobeItem real) {
    final current = state.asData?.value ?? const <WardrobeItem>[];
    final next = [for (final i in current) if (i.id == tempId) real else i];
    if (!next.any((i) => i.id == real.id)) next.insert(0, real);
    state = AsyncData(next);
    _arm(state.requireValue);
  }

  void _removePending(String tempId) {
    final current = state.asData?.value ?? const <WardrobeItem>[];
    state = AsyncData([for (final i in current) if (i.id != tempId) i]);
    final items = state.asData?.value;
    if (items != null) _arm(items);
  }

  /// Optimistically flag an existing item as enhancing (detail-screen "Enhance"),
  /// so the badge + polling start immediately instead of after a refetch.
  void markEnhancing(String itemId) {
    final current = state.asData?.value;
    if (current == null) {
      refresh();
      return;
    }
    state = AsyncData([
      for (final i in current)
        if (i.id == itemId) i.copyWith(aiStatus: 'queued') else i,
    ]);
    _arm(state.requireValue);
  }
}

final wardrobeItemsProvider =
    AsyncNotifierProvider.autoDispose<WardrobeItemsNotifier, List<WardrobeItem>>(
      WardrobeItemsNotifier.new,
    );

/// Current closet search query (empty = browse the whole closet). Set on submit.
class WardrobeSearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) => state = query.trim();
}

final wardrobeSearchQueryProvider =
    NotifierProvider<WardrobeSearchQuery, String>(WardrobeSearchQuery.new);

/// What the wardrobe screen renders: the full closet when the query is empty,
/// otherwise semantic search results (§2.1).
/// Semantic search results — only fetched while a query is active.
final wardrobeSearchResultsProvider = FutureProvider.autoDispose<List<WardrobeItem>>((
  ref,
) {
  final query = ref.watch(wardrobeSearchQueryProvider).trim();
  if (query.isEmpty) return Future.value(const []);
  return ref.watch(wardrobeRepositoryProvider).search(query: query);
});

/// What the wardrobe screen renders. When browsing (no query) it MIRRORS the
/// closet's AsyncValue directly: the poll updates that notifier via `state =`
/// (data → data, never a loading transition), so the grid updates live — the
/// cutout / enhanced cover appears on its own — WITHOUT the reload flicker a
/// re-running FutureProvider caused (item briefly vanished then reappeared).
final wardrobeViewProvider =
    Provider.autoDispose<AsyncValue<List<WardrobeItem>>>((ref) {
      final query = ref.watch(wardrobeSearchQueryProvider).trim();
      if (query.isEmpty) return ref.watch(wardrobeItemsProvider);
      return ref.watch(wardrobeSearchResultsProvider);
    });
