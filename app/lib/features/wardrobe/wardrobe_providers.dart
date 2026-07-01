import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/wardrobe_analytics.dart';
import '../../data/models/wardrobe_gap.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/wardrobe_repository.dart';

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
      final items = await ref.read(wardrobeRepositoryProvider).getItems();
      _errorStreak = 0;
      state = AsyncData(items);
      _arm(items);
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

  /// Surface a just-added item as "processing" the INSTANT the closet is shown —
  /// no waiting on the first network refetch (which is what made the badges lag a
  /// second behind the "added" toast). The 2s poll then converges on server
  /// truth (real cutout/cover). `enhancing` also shows the "Enhancing…" pill.
  void addOptimistic(WardrobeItem item, {bool enhancing = false}) {
    final optimistic = enhancing ? item.copyWith(aiStatus: 'queued') : item;
    final current = state.asData?.value;
    if (current == null) {
      refresh(); // initial closet still loading — a full fetch includes it
      return;
    }
    state = AsyncData([
      optimistic,
      for (final i in current)
        if (i.id != item.id) i,
    ]);
    _arm(state.requireValue);
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
final wardrobeViewProvider = FutureProvider.autoDispose<List<WardrobeItem>>((
  ref,
) async {
  final query = ref.watch(wardrobeSearchQueryProvider).trim();
  if (query.isEmpty) {
    // Depend on the closet's AsyncValue ITSELF (not only `.future`) so this view
    // re-runs on every imperative state update — including the 4s poll ticks
    // that flip a cutout / AI-enhance to done. Watching `.future` alone left the
    // grid stale until a tab switch forced an autoDispose re-fetch: the enhanced
    // cover / cutout only showed after leaving and re-entering the closet.
    ref.watch(wardrobeItemsProvider);
    return ref.watch(wardrobeItemsProvider.future);
  }
  return ref.watch(wardrobeRepositoryProvider).search(query: query);
});
