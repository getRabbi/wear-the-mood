import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/packing_plan.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'packing_controller.dart';

const _dayOptions = [2, 3, 5, 7];

/// Packing planner (CLAUDE.md §24) — a packing list from the user's own closet,
/// trip-length + occasion aware. All four states (§4.3).
class PackingScreen extends ConsumerStatefulWidget {
  const PackingScreen({super.key});

  @override
  ConsumerState<PackingScreen> createState() => _PackingScreenState();
}

class _PackingScreenState extends ConsumerState<PackingScreen> {
  final _occasion = TextEditingController();
  int _days = 3;

  @override
  void dispose() {
    _occasion.dispose();
    super.dispose();
  }

  void _plan() {
    ref
        .read(packingControllerProvider.notifier)
        .plan(days: _days, occasion: _occasion.text);
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
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            Text(l10n.packingDaysLabel, style: text.titleMedium),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
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
            TextField(
              controller: _occasion,
              decoration: InputDecoration(
                labelText: l10n.packingOccasionHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
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
                  : _PackingResult(plan: plan),
            ),
          ],
        ),
      ),
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

class _PackingResult extends StatelessWidget {
  const _PackingResult({required this.plan});

  final PackingPlan plan;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(plan.title, style: text.headlineSmall),
        if (plan.notes.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(plan.notes.trim(), style: text.bodyMedium),
        ],
        const SizedBox(height: AppSpace.lg),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: AppSpace.md,
            crossAxisSpacing: AppSpace.md,
            childAspectRatio: 0.6,
          ),
          itemCount: plan.items.length,
          itemBuilder: (context, i) {
            final item = plan.items[i];
            return OutfitTile(
              imageUrl: item.displayImageUrl ?? '',
              label: item.title,
            );
          },
        ),
      ],
    );
  }
}
