import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../data/repositories/profile_repository.dart';
import '../../features/onboarding/onboarding_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../home/wtm_mood.dart';
import '../widgets/widgets.dart';

/// WTM Onboarding (board §3.3, P10) — the three-step primer: a mood baseline,
/// style tags (which seed the Style DNA), and a body-photo invite. Skippable;
/// finishing marks onboarding complete and enters the app.
class WtmOnboardingScreen extends ConsumerStatefulWidget {
  const WtmOnboardingScreen({super.key});

  @override
  ConsumerState<WtmOnboardingScreen> createState() =>
      _WtmOnboardingScreenState();
}

class _WtmOnboardingScreenState extends ConsumerState<WtmOnboardingScreen> {
  static const _tags = [
    'Romantic', 'Street', 'Minimal', 'Bold', 'Classic', 'Edgy', 'Boho', 'Glam',
  ];
  int _step = 0;
  final _selected = <String>{};
  bool _busy = false;

  Future<void> _finish() async {
    setState(() => _busy = true);
    // Best-effort: seed Style DNA from the picked tags (needs a session).
    if (_selected.isNotEmpty) {
      try {
        await ref
            .read(profileRepositoryProvider)
            .updateProfile(styleTags: _selected.toList());
      } catch (_) {/* onboarding proceeds regardless */}
    }
    try {
      await ref.read(onboardingRepositoryProvider).markComplete();
    } catch (_) {}
    if (mounted) context.go(AppRoute.wtmHome);
  }

  void _next() {
    if (_step < 2) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return WtmScaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuroraBox(
            borderRadius: BorderRadius.zero,
            border: false,
            vignette: true,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: i <= _step
                                  ? WtmColors.gold
                                  : WtmColors.line,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: WtmSpace.s12),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _busy ? null : _finish,
                        child: Text(l10n.wtmObSkip,
                            style: WtmType.micro.copyWith(color: WtmColors.gold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: WtmSpace.s22),
                  Expanded(
                    child: switch (_step) {
                      0 => _MoodStep(l10n: l10n),
                      1 => _TagsStep(
                          l10n: l10n,
                          tags: _tags,
                          selected: _selected,
                          onToggle: (t) => setState(() => _selected.contains(t)
                              ? _selected.remove(t)
                              : _selected.add(t)),
                        ),
                      _ => _BodyStep(l10n: l10n),
                    },
                  ),
                  GradientCta(
                    label: _step < 2 ? l10n.wtmObNext : l10n.wtmObEnter,
                    onPressed: _busy ? null : _next,
                  ),
                  const SizedBox(height: WtmSpace.s22),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodStep extends ConsumerWidget {
  const _MoodStep({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mood = ref.watch(wtmMoodProvider);
    final zone = WtmMoodZone.of(mood);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.wtmObMoodTitle, style: WtmType.h1.copyWith(fontSize: 26)),
        const SizedBox(height: WtmSpace.s8),
        Text(l10n.wtmObMoodSub, style: WtmType.sub),
        const Spacer(),
        WtmSlider(
          value: mood,
          onChanged: ref.read(wtmMoodProvider.notifier).preview,
          onChangeEnd: ref.read(wtmMoodProvider.notifier).commit,
          fill: false,
          height: 4,
          semanticLabel: l10n.wtmMoodEyebrow,
          trackGradient: const LinearGradient(
            colors: [
              Color(0xFF6F86D6),
              Color(0xFF9B7BE8),
              Color(0xFFC77DFF),
              Color(0xFFF3A0C8),
            ],
            stops: [0.0, 0.35, 0.65, 1.0],
          ),
        ),
        const SizedBox(height: WtmSpace.s10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final z in WtmMoodZone.values)
              Text(
                switch (z) {
                  WtmMoodZone.calm => l10n.wtmMoodCalm,
                  WtmMoodZone.confident => l10n.wtmMoodConfident,
                  WtmMoodZone.bold => l10n.wtmMoodBold,
                  WtmMoodZone.rebel => l10n.wtmMoodRebel,
                },
                style: z == zone
                    ? WtmType.micro.copyWith(color: WtmColors.gold)
                    : WtmType.micro,
              ),
          ],
        ),
        const Spacer(),
      ],
    );
  }
}

class _TagsStep extends StatelessWidget {
  const _TagsStep({
    required this.l10n,
    required this.tags,
    required this.selected,
    required this.onToggle,
  });

  final AppLocalizations l10n;
  final List<String> tags;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.wtmObTagsTitle, style: WtmType.h1.copyWith(fontSize: 26)),
        const SizedBox(height: WtmSpace.s8),
        Text(l10n.wtmObTagsSub, style: WtmType.sub),
        const SizedBox(height: WtmSpace.s18),
        Wrap(
          spacing: WtmSpace.s8,
          runSpacing: WtmSpace.s8,
          children: [
            for (final tag in tags)
              WtmChip(
                label: tag,
                on: selected.contains(tag),
                onTap: () => onToggle(tag),
              ),
          ],
        ),
      ],
    );
  }
}

class _BodyStep extends StatelessWidget {
  const _BodyStep({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.wtmObBodyTitle, style: WtmType.h1.copyWith(fontSize: 26)),
        const SizedBox(height: WtmSpace.s8),
        Text(l10n.wtmObBodySub, style: WtmType.sub),
        const SizedBox(height: WtmSpace.s16),
        Expanded(
          child: Center(
            child: AuroraBox(
              width: 180,
              height: 260,
              borderRadius: WtmRadius.arch,
              vignette: true,
              child: const Center(
                child: SizedBox(
                  width: 120,
                  height: 220,
                  child: WtmFigure(WtmFigureKind.body, opacity: 0.8),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: WtmSpace.s12),
        GhostButton(
          label: l10n.wtmObBodyAdd,
          icon: const WtmIcon(WtmGlyph.camera, size: 15, color: WtmColors.text),
          onPressed: () => context.push(AppRoute.wtmBodyPhoto),
        ),
      ],
    );
  }
}
