import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/calendar_event_plan.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'calendar_controller.dart';

/// Calendar autopilot (CLAUDE.md §24) — an outfit for each upcoming event. The
/// user adds events (auto-import from the device calendar is gated on a plugin +
/// permission, §25). All four states (§4.3).
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  final _field = TextEditingController();
  final List<String> _events = [];

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _add() {
    final title = _field.text.trim();
    if (title.isEmpty) return;
    setState(() {
      _events.add(title);
      _field.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(calendarControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.calendarTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            Text(l10n.calendarIntro, style: text.bodyMedium),
            const SizedBox(height: AppSpace.lg),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _field,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _add(),
                    decoration: InputDecoration(
                      hintText: l10n.calendarAddHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                IconButton.filled(
                  onPressed: _add,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            if (_events.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Wrap(
                spacing: AppSpace.sm,
                children: [
                  for (final (i, e) in _events.indexed)
                    InputChip(
                      label: Text(e),
                      onDeleted: () => setState(() => _events.removeAt(i)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpace.sm),
            TextButton.icon(
              onPressed: () => _snack(l10n.calendarImportSoon),
              icon: const Icon(Icons.event_available_outlined, size: 18),
              label: Text(l10n.calendarImport),
            ),
            const SizedBox(height: AppSpace.md),
            PrimaryButton(
              label: l10n.calendarPlan,
              icon: Icons.auto_awesome,
              isLoading: state.isLoading,
              onPressed: (_events.isEmpty || state.isLoading)
                  ? null
                  : () => ref
                        .read(calendarControllerProvider.notifier)
                        .plan(List.of(_events)),
            ),
            const SizedBox(height: AppSpace.xl),
            state.when(
              loading: () => PremiumLogoLoader(label: l10n.commonLoading),
              error: (_, _) => ErrorState(
                title: l10n.calendarErrorTitle,
                onRetry: () => ref
                    .read(calendarControllerProvider.notifier)
                    .plan(List.of(_events)),
              ),
              data: (plans) => plans == null
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        for (final plan in plans) _EventPlanCard(plan: plan),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventPlanCard extends StatelessWidget {
  const _EventPlanCard({required this.plan});

  final CalendarEventPlan plan;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final items = plan.suggestion.items;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plan.title, style: text.titleMedium),
            const SizedBox(height: AppSpace.xs),
            Text(
              plan.suggestion.title,
              style: text.bodyMedium?.copyWith(color: AppColors.accent),
            ),
            if (plan.suggestion.rationale.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpace.xs),
              Text(plan.suggestion.rationale.trim(), style: text.bodySmall),
            ],
            if (items.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
                  itemBuilder: (context, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: SizedBox(
                      width: 90,
                      child:
                          (items[i].displayImageUrl != null &&
                              items[i].displayImageUrl!.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: items[i].displayImageUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) =>
                                  const ColoredBox(color: AppColors.mist),
                            )
                          : const ColoredBox(color: AppColors.mist),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
