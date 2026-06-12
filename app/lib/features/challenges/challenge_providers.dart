import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/challenge.dart';
import '../../data/models/challenge_entry.dart';
import '../../data/repositories/challenges_repository.dart';

/// Active challenges for the challenges list.
final challengesProvider = FutureProvider<List<Challenge>>((ref) {
  return ref.read(challengesRepositoryProvider).listChallenges();
});

/// One challenge by slug (deep-link friendly). Auto-disposes with the detail
/// screen so re-opening refetches fresh counts.
final challengeProvider = FutureProvider.autoDispose.family<Challenge, String>((
  ref,
  slug,
) {
  return ref.read(challengesRepositoryProvider).getChallenge(slug);
});

/// Newest-first entries for a challenge, keyed by challenge id.
final challengeEntriesProvider = FutureProvider.autoDispose
    .family<List<ChallengeEntry>, String>((ref, challengeId) {
      return ref.read(challengesRepositoryProvider).getEntries(challengeId);
    });
