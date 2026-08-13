import 'dart:async';

import 'package:app/data/models/tryon_result.dart';
import 'package:app/data/repositories/tryon_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Seeded try-on history, with delete wired to whatever the test wants.
///
/// Overriding [TryOnResults.build] rather than the repository keeps the
/// notifier's own optimistic-remove-and-restore logic in play, which is the
/// behaviour the deletion tests are actually about.
class FakeTryOnResults extends TryOnResults {
  FakeTryOnResults(this._seed, {this.onDelete});

  final List<TryonResult> _seed;

  /// Called instead of the network. Throw from here to exercise the restore
  /// path; leave null for a delete that always succeeds.
  final Future<void> Function(String id)? onDelete;

  /// Every id this fake was asked to delete, in order.
  final deleted = <String>[];

  @override
  Future<List<TryonResult>> build() async => [
    // Deletions are SERVER state, so a reload must not resurrect them. A fake
    // that kept answering with the seed would let a cosmetic delete pass.
    for (final result in _seed)
      if (!deleted.contains(result.id)) result,
  ];

  @override
  Future<void> delete(String resultId) async {
    final current = state.asData?.value;
    if (current == null) return;
    final index = current.indexWhere((r) => r.id == resultId);
    if (index < 0) return;

    final removed = current[index];
    state = AsyncData([
      for (final result in current)
        if (result.id != resultId) result,
    ]);
    deleted.add(resultId);
    try {
      await onDelete?.call(resultId);
    } catch (_) {
      final latest = state.asData?.value ?? const <TryonResult>[];
      state = AsyncData(
        [...latest]..insert(index.clamp(0, latest.length), removed),
      );
      rethrow;
    }
  }
}

/// History whose load never completes — for loading-state tests.
class LoadingTryOnResults extends TryOnResults {
  @override
  Future<List<TryonResult>> build() => Completer<List<TryonResult>>().future;
}

/// History whose load fails — for error/retry-state tests.
class FailingTryOnResults extends TryOnResults {
  @override
  Future<List<TryonResult>> build() async => throw StateError('offline');
}
