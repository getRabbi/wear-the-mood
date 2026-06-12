import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/calendar_event_plan.dart';
import '../../data/repositories/calendar_repository.dart';

/// Drives calendar autopilot. Idle is AsyncData(null); planning replaces it with
/// an outfit per event. The stylist runs server-side and falls back gracefully
/// (§24), so a success here can still be the stub's outfits.
class CalendarController extends Notifier<AsyncValue<List<CalendarEventPlan>?>> {
  @override
  AsyncValue<List<CalendarEventPlan>?> build() => const AsyncData(null);

  Future<void> plan(List<String> eventTitles) async {
    if (state.isLoading || eventTitles.isEmpty) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(calendarRepositoryProvider).plan(eventTitles),
    );
  }

  void reset() => state = const AsyncData(null);
}

final calendarControllerProvider =
    NotifierProvider<CalendarController, AsyncValue<List<CalendarEventPlan>?>>(
      CalendarController.new,
    );
