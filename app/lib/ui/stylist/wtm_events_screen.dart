import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../data/models/planner.dart';
import '../../data/repositories/planner_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Event Planner (RETENTION spec §15).
///
/// Deliberately small. It stores what the user TYPED — a name, a date, an
/// occasion, optionally the look they picked for it. No calendar permission is
/// requested, no calendar is read and none is written; that integration is a
/// separate, permission-aware project (§45 "do not overbuild").
///
/// Reminders are opt-in **per event** and default off, so saving something to
/// remember is never mistaken for consent to be messaged about it.
class WtmEventsScreen extends ConsumerWidget {
  const WtmEventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final events = ref.watch(upcomingEventsProvider);

    return WtmPage(
      title: l10n.eventsTitle,
      children: [
        ...events.when<List<Widget>>(
          skipLoadingOnReload: true,
          loading: () => const [
            LoadingShimmer(width: double.infinity, height: 74),
            SizedBox(height: WtmSpace.s10),
            LoadingShimmer(width: double.infinity, height: 74),
          ],
          error: (_, _) => [
            const SizedBox(height: WtmSpace.s22),
            WtmErrorState(
              title: l10n.errorGenericTitle,
              message: l10n.eventsError,
              retryLabel: l10n.commonRetry,
              onRetry: () => ref.invalidate(upcomingEventsProvider),
            ),
          ],
          data: (list) => list.events.isEmpty
              ? [
                  const SizedBox(height: WtmSpace.s22),
                  WtmEmptyState(
                    glyph: WtmGlyph.bookmark,
                    title: l10n.eventsEmptyTitle,
                    message: l10n.eventsEmptyMessage,
                    ctaLabel: l10n.eventsAdd,
                    onCta: () => _add(context, ref),
                  ),
                ]
              : [
                  for (final event in list.events) ...[
                    _EventRow(
                      event: event,
                      onDelete: () => _delete(context, ref, event),
                    ),
                    const SizedBox(height: WtmSpace.s10),
                  ],
                  const SizedBox(height: WtmSpace.s6),
                  GhostButton(
                    label: l10n.eventsAdd,
                    onPressed: () => _add(context, ref),
                  ),
                ],
        ),
        const SizedBox(height: WtmSpace.s22),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final draft = await showModalBottomSheet<_EventDraft>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _EventSheet(),
    );
    if (draft == null) return;
    final created = await ref
        .read(plannerRepositoryProvider)
        .createEvent(
          name: draft.name,
          eventAt: draft.date,
          reminderOptIn: draft.reminder,
        );
    ref.invalidate(upcomingEventsProvider);
    if (created != null) {
      await ref
          .read(analyticsProvider)
          .track(
            AnalyticsEvents.eventCreated,
            // Never the event's NAME: that is the user's own content, and §32
            // forbids putting raw user text into analytics.
            properties: {'reminder': draft.reminder},
          );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    StyleEvent event,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await wtmConfirmDialog(
      context,
      title: l10n.eventDelete,
      message: event.name,
      confirmLabel: l10n.eventDelete,
      danger: true,
    );
    if (!confirmed) return;
    await ref.read(plannerRepositoryProvider).deleteEvent(event.id);
    ref.invalidate(upcomingEventsProvider);
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.onDelete});

  final StyleEvent event;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Relative, because "in 3 days" is the thing a user actually acts on. The
    // absolute date is in the sheet when they open it.
    final when = switch (event) {
      _ when event.isPast => l10n.eventPast,
      _ when event.daysAway == 0 => l10n.eventToday,
      _ when event.daysAway == 1 => l10n.eventTomorrow,
      _ => l10n.eventInDays(event.daysAway),
    };
    return WtmRow(
      glyph: WtmGlyph.bookmark,
      title: event.name,
      subtitle: event.occasion == null ? when : '$when · ${event.occasion}',
      trailing: WtmIconButton(
        WtmGlyph.erase,
        semanticLabel: l10n.eventDelete,
        onTap: onDelete,
      ),
    );
  }
}

/// What the sheet collected. A plain record rather than a partially-built
/// [StyleEvent], so an unsaved draft can never be mistaken for a saved event.
class _EventDraft {
  const _EventDraft({
    required this.name,
    required this.date,
    required this.reminder,
  });

  final String name;
  final DateTime date;
  final bool reminder;
}

class _EventSheet extends StatefulWidget {
  const _EventSheet();

  @override
  State<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<_EventSheet> {
  final _name = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 7));
  bool _reminder = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      // Lifts the sheet clear of the keyboard while the name field has focus.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(WtmSpace.screenH),
          padding: const EdgeInsets.all(WtmSpace.s18),
          // Same cap and scroll as the reason sheet, and for a sharper reason:
          // this one opens a KEYBOARD. On a 320x640dp phone at 2.0x text, the
          // title, field, date row, reminder switch and CTA do not fit the
          // remaining space, and the Save button — the only way to finish — is
          // what falls off the bottom.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          decoration: BoxDecoration(
            color: WtmColors.panel,
            borderRadius: BorderRadius.circular(WtmRadius.sheetTop),
            border: Border.all(color: WtmColors.line),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.eventsAdd, style: WtmType.h2.copyWith(fontSize: 19)),
                const SizedBox(height: WtmSpace.s14),
                Text(
                  l10n.eventName,
                  style: WtmType.label.copyWith(color: WtmColors.muted),
                ),
                const SizedBox(height: WtmSpace.s6),
                TextField(
                  controller: _name,
                  style: WtmType.body,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: l10n.eventNameHint,
                    hintStyle: WtmType.sub,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(WtmRadius.card),
                      borderSide: const BorderSide(color: WtmColors.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(WtmRadius.card),
                      borderSide: const BorderSide(color: WtmColors.gold),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: WtmSpace.s14),
                WtmRow(
                  glyph: WtmGlyph.bookmark,
                  title: l10n.eventDate,
                  subtitle: '${_date.day}/${_date.month}/${_date.year}',
                  onTap: _pickDate,
                ),
                const SizedBox(height: WtmSpace.s10),
                WtmRow(
                  glyph: WtmGlyph.bell,
                  title: l10n.eventReminder,
                  trailing: Switch(
                    value: _reminder,
                    onChanged: (value) => setState(() => _reminder = value),
                    activeTrackColor: WtmColors.gold,
                  ),
                ),
                const SizedBox(height: WtmSpace.s16),
                GradientCta(
                  label: l10n.eventSave,
                  onPressed: _name.text.trim().isEmpty ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      // Today is a legitimate event date; yesterday is not something to plan.
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _save() {
    Navigator.of(context).pop(
      _EventDraft(
        name: _name.text.trim(),
        // Midday, not midnight: an event stored at 00:00 local reads as the
        // previous day in any zone behind the one it was created in.
        date: DateTime(_date.year, _date.month, _date.day, 12),
        reminder: _reminder,
      ),
    );
  }
}
