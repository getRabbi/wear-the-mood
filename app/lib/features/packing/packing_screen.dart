import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/packing_plan.dart';
import '../../data/models/wardrobe_item.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'packing_controller.dart';

const _dayOptions = [2, 3, 4, 5, 7, 10, 14];

/// Trip climate options (drives layering advice; no external weather API needed,
/// per spec — manual selection is the fallback).
enum _Climate { hot, cold, rainy, mixed }

/// Trip activities — multi-select, shape the list (work pieces, beachwear …).
enum _Activity { casual, work, university, party, beach, wedding, travel }

/// Packing planner (CLAUDE.md §24) — a modern, trip-aware list from the user's
/// own closet. Richer inputs (destination, climate, activities, laundry, modest)
/// are composed into the existing planner request (no backend change); the
/// result is grouped by category with packed/unpacked check-off. All four
/// states (§4.3).
class PackingScreen extends ConsumerStatefulWidget {
  const PackingScreen({super.key});

  @override
  ConsumerState<PackingScreen> createState() => _PackingScreenState();
}

class _PackingScreenState extends ConsumerState<PackingScreen> {
  final _destination = TextEditingController();
  int _days = 3;
  _Climate _climate = _Climate.mixed;
  final Set<_Activity> _activities = {_Activity.casual};
  bool _laundry = false;
  bool _modest = false;
  // Pieces the user has ticked off as packed (per result, in-memory).
  final Set<String> _packed = {};

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  String _climateLabel(AppLocalizations l10n, _Climate c) => switch (c) {
    _Climate.hot => l10n.packingClimateHot,
    _Climate.cold => l10n.packingClimateCold,
    _Climate.rainy => l10n.packingClimateRainy,
    _Climate.mixed => l10n.packingClimateMixed,
  };

  String _activityLabel(AppLocalizations l10n, _Activity a) => switch (a) {
    _Activity.casual => l10n.packingActivityCasual,
    _Activity.work => l10n.packingActivityWork,
    _Activity.university => l10n.packingActivityUniversity,
    _Activity.party => l10n.packingActivityParty,
    _Activity.beach => l10n.packingActivityBeach,
    _Activity.wedding => l10n.packingActivityWedding,
    _Activity.travel => l10n.packingActivityTravel,
  };

  void _plan() {
    final l10n = AppLocalizations.of(context);
    // Primary occasion = first chosen activity; the rest become context notes
    // the planner (LLM or heuristic) can use — no schema change needed.
    final occasion = _activities.isEmpty
        ? null
        : _activityLabel(l10n, _activities.first);
    final parts = <String>[
      if (_destination.text.trim().isNotEmpty)
        'Destination: ${_destination.text.trim()}',
      'Climate: ${_climateLabel(l10n, _climate)}',
      if (_activities.isNotEmpty)
        'Activities: ${_activities.map((a) => _activityLabel(l10n, a)).join(', ')}',
      if (_laundry) 'Laundry access available — pack lighter',
      if (_modest) 'Modest / hijab-friendly styling',
    ];
    setState(() => _packed.clear());
    ref
        .read(packingControllerProvider.notifier)
        .plan(days: _days, occasion: occasion, note: parts.join('. '));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(packingControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.packingTitle)),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.lg,
            AppSpace.lg,
            bottomNavClearance(context),
          ),
          children: [
            _Label(l10n.packingDaysLabel),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final d in _dayOptions)
                  AppChip(
                    label: l10n.packingDays(d),
                    selected: _days == d,
                    onTap: () => setState(() => _days = d),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            _Label(l10n.packingDestinationLabel),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: _destination,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: l10n.packingDestinationHint,
                prefixIcon: const Icon(Icons.place_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            _Label(l10n.packingClimateLabel),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final c in _Climate.values)
                  AppChip(
                    label: _climateLabel(l10n, c),
                    selected: _climate == c,
                    onTap: () => setState(() => _climate = c),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            _Label(l10n.packingActivitiesLabel),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (final a in _Activity.values)
                  AppChip(
                    label: _activityLabel(l10n, a),
                    selected: _activities.contains(a),
                    onTap: () => setState(() {
                      if (!_activities.add(a)) _activities.remove(a);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _laundry,
              onChanged: (v) => setState(() => _laundry = v),
              title: Text(l10n.packingLaundryLabel, style: text.bodyMedium),
              subtitle: Text(
                l10n.packingLaundrySubtitle,
                style: text.bodySmall?.copyWith(color: AppColors.graphite),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _modest,
              onChanged: (v) => setState(() => _modest = v),
              title: Text(l10n.packingModestLabel, style: text.bodyMedium),
              subtitle: Text(
                l10n.packingModestSubtitle,
                style: text.bodySmall?.copyWith(color: AppColors.graphite),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            PrimaryButton(
              label: l10n.packingCta,
              icon: Icons.luggage_outlined,
              isLoading: state.isLoading,
              onPressed: state.isLoading ? null : _plan,
            ),
            const SizedBox(height: AppSpace.xl),
            state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => ErrorState(
                title: l10n.packingErrorTitle,
                onRetry: _plan,
              ),
              data: (plan) => plan == null
                  ? _Intro(message: l10n.packingIntro)
                  : _PackingResult(
                      plan: plan,
                      packed: _packed,
                      onTogglePacked: (id) => setState(() {
                        if (!_packed.add(id)) _packed.remove(id);
                      }),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
      child: Column(
        children: [
          const Icon(Icons.luggage_outlined, size: 48, color: AppColors.graphite),
          const SizedBox(height: AppSpace.md),
          Text(message, style: text.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Packing list grouped by category, each piece a check-off card (spec).
class _PackingResult extends StatelessWidget {
  const _PackingResult({
    required this.plan,
    required this.packed,
    required this.onTogglePacked,
  });

  final PackingPlan plan;
  final Set<String> packed;
  final void Function(String id) onTogglePacked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final groups = groupPackingItems(plan.items);
    final packedCount = plan.items.where((i) => packed.contains(i.id)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(plan.title, style: text.headlineSmall)),
            if (plan.items.isNotEmpty)
              Text(
                l10n.packingPackedCount(packedCount, plan.items.length),
                style: text.bodySmall?.copyWith(color: AppColors.graphite),
              ),
          ],
        ),
        if (plan.notes.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(plan.notes.trim(), style: text.bodyMedium),
        ],
        const SizedBox(height: AppSpace.lg),
        if (plan.items.isEmpty)
          _MissingPieces(message: l10n.packingMissingPieces)
        else
          for (final (group, items) in groups) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text(
                group.label(l10n),
                style: text.labelLarge?.copyWith(color: AppColors.graphite),
              ),
            ),
            for (final item in items)
              _PackItemRow(
                item: item,
                packed: packed.contains(item.id),
                onToggle: () => onTogglePacked(item.id),
              ),
            const SizedBox(height: AppSpace.md),
          ],
      ],
    );
  }
}

class _PackItemRow extends StatelessWidget {
  const _PackItemRow({
    required this.item,
    required this.packed,
    required this.onToggle,
  });

  final WardrobeItem item;
  final bool packed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: SmartImageCard(
                    imageUrl: item.displayImageUrl ?? '',
                    aspectRatio: 1,
                    fit: BoxFit.contain,
                    padded: true,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(
                    item.title ?? l10n.closetNeedsCategory,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      decoration: packed ? TextDecoration.lineThrough : null,
                      color: packed ? AppColors.graphite : null,
                    ),
                  ),
                ),
                Icon(
                  packed
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: packed ? AppColors.success : AppColors.graphite,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MissingPieces extends StatelessWidget {
  const _MissingPieces({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.accent),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              message,
              style: text.bodySmall?.copyWith(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// Output groups for a packing list.
enum PackingGroup { tops, bottoms, dresses, outerwear, shoes, bags, hijab, accessories, essentials }

extension on PackingGroup {
  String label(AppLocalizations l10n) => switch (this) {
    PackingGroup.tops => l10n.packingGroupTops,
    PackingGroup.bottoms => l10n.packingGroupBottoms,
    PackingGroup.dresses => l10n.packingGroupDresses,
    PackingGroup.outerwear => l10n.packingGroupOuterwear,
    PackingGroup.shoes => l10n.packingGroupShoes,
    PackingGroup.bags => l10n.packingGroupBags,
    PackingGroup.hijab => l10n.packingGroupHijab,
    PackingGroup.accessories => l10n.packingGroupAccessories,
    PackingGroup.essentials => l10n.packingGroupEssentials,
  };

  List<String> get _keywords => switch (this) {
    PackingGroup.tops => const ['top', 'shirt', 'tee', 'blouse', 'sweater', 'knit', 'hoodie', 'tunic', 'kurti'],
    PackingGroup.bottoms => const ['bottom', 'pant', 'trouser', 'jean', 'short', 'skirt', 'legging'],
    PackingGroup.dresses => const ['dress', 'gown', 'jumpsuit', 'traditional'],
    PackingGroup.outerwear => const ['jacket', 'coat', 'blazer', 'outer', 'trench', 'parka', 'puffer', 'winter'],
    PackingGroup.shoes => const ['shoe', 'sneaker', 'boot', 'heel', 'sandal', 'loafer'],
    PackingGroup.bags => const ['bag', 'purse', 'tote', 'clutch', 'backpack'],
    PackingGroup.hijab => const ['hijab', 'scarf', 'shawl'],
    PackingGroup.accessories => const ['accessor', 'belt', 'glass', 'jewel', 'watch', 'hat', 'cap'],
    PackingGroup.essentials => const [],
  };

  bool matches(WardrobeItem item) {
    final t = '${item.category ?? ''} ${item.title ?? ''} ${item.tags.join(' ')}'.toLowerCase();
    return _keywords.any(t.contains);
  }
}

/// Group packing items by category, preserving order; unmatched → Essentials.
List<(PackingGroup, List<WardrobeItem>)> groupPackingItems(
  List<WardrobeItem> items,
) {
  final result = <PackingGroup, List<WardrobeItem>>{};
  for (final item in items) {
    var placed = false;
    for (final group in PackingGroup.values) {
      if (group == PackingGroup.essentials) continue;
      if (group.matches(item)) {
        (result[group] ??= []).add(item);
        placed = true;
        break;
      }
    }
    if (!placed) (result[PackingGroup.essentials] ??= []).add(item);
  }
  return [
    for (final group in PackingGroup.values)
      if (result[group]?.isNotEmpty ?? false) (group, result[group]!),
  ];
}
