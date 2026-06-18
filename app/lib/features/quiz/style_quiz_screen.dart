import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/quiz.dart';
import '../../data/repositories/quiz_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../social/compose_post_screen.dart';
import 'style_dna_card.dart';

/// The Style Quiz flow (FEATURES_COMMUNITY_PLUS · Style Quiz): one question per
/// screen with a progress bar, then a shareable "Style DNA" result. Re-takeable.
class StyleQuizScreen extends ConsumerStatefulWidget {
  const StyleQuizScreen({super.key});

  @override
  ConsumerState<StyleQuizScreen> createState() => _StyleQuizScreenState();
}

class _StyleQuizScreenState extends ConsumerState<StyleQuizScreen> {
  final Map<String, String> _answers = {};
  final _cardKey = GlobalKey();
  int _index = 0;
  QuizResult? _result;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).track(AnalyticsEvents.quizStarted);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _select(ActiveQuiz quiz, QuizQuestion question, String key) {
    _answers[question.id] = key;
    if (_index < quiz.questions.length - 1) {
      setState(() => _index++);
    } else {
      _submit(quiz);
    }
  }

  Future<void> _submit(ActiveQuiz quiz) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _submitting = true);
    try {
      final result =
          await ref.read(quizRepositoryProvider).submit(quiz.id, _answers);
      await ref.read(analyticsProvider).track(AnalyticsEvents.quizCompleted);
      ref.invalidate(latestQuizResultProvider);
      if (mounted) setState(() => _result = result);
    } on ApiException {
      _snack(l10n.quizSubmitError);
    } catch (_) {
      _snack(l10n.quizSubmitError);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _retake() {
    setState(() {
      _answers.clear();
      _index = 0;
      _result = null;
    });
    ref.read(analyticsProvider).track(AnalyticsEvents.quizStarted);
  }

  /// Renders the Style DNA card to a PNG so it can be shared as a community post.
  Future<Uint8List?> _capture() async {
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null; // sharing falls back to an empty composer
    }
  }

  Future<void> _share() async {
    final bytes = await _capture();
    await ref.read(analyticsProvider).track(AnalyticsEvents.quizResultShared);
    if (!mounted) return;
    context.push(
      AppRoute.socialCompose,
      extra: bytes != null ? ComposeArgs(presetPhoto: bytes) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_result != null ? l10n.quizResultTitle : l10n.quizHomeTitle),
      ),
      body: SafeArea(
        child: _result != null
            ? _ResultView(
                cardKey: _cardKey,
                result: _result!.result,
                onShare: _share,
                onRetake: _retake,
                onSave: () {
                  _snack(l10n.quizSaved);
                  context.pop();
                },
              )
            : _submitting
                ? const Center(child: CircularProgressIndicator())
                : ref.watch(activeQuizProvider).when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (_, _) => ErrorState(
                        title: l10n.quizError,
                        onRetry: () => ref.invalidate(activeQuizProvider),
                      ),
                      data: (quiz) => _QuestionView(
                        quiz: quiz,
                        index: _index,
                        selectedKey: _answers[quiz.questions[_index].id],
                        onSelect: (key) =>
                            _select(quiz, quiz.questions[_index], key),
                      ),
                    ),
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({
    required this.quiz,
    required this.index,
    required this.selectedKey,
    required this.onSelect,
  });

  final ActiveQuiz quiz;
  final int index;
  final String? selectedKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final question = quiz.questions[index];
    final total = quiz.questions.length;
    final progress = total == 0 ? 0.0 : (index + 1) / total;

    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.mist,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            l10n.quizProgress(index + 1, total),
            style: text.bodySmall?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpace.lg),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.base,
              switchInCurve: AppMotion.easing,
              child: Column(
                key: ValueKey(question.id),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(question.prompt, style: text.headlineSmall),
                  const SizedBox(height: AppSpace.lg),
                  for (final option in question.options) ...[
                    _OptionTile(
                      label: option.label,
                      selected: option.key == selectedKey,
                      onTap: () => onSelect(option.key),
                    ),
                    const SizedBox(height: AppSpace.md),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.md);
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentSoft
              : Theme.of(context).colorScheme.surface,
          borderRadius: radius,
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: text.titleMedium?.copyWith(
                  color: selected ? AppColors.accent : AppColors.ink,
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? AppColors.accent : AppColors.graphite,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.cardKey,
    required this.result,
    required this.onShare,
    required this.onRetake,
    required this.onSave,
  });

  final GlobalKey cardKey;
  final StyleResult result;
  final VoidCallback onShare;
  final VoidCallback onRetake;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The reveal: a one-shot scale + fade (§4 motion).
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: AppMotion.base,
            curve: AppMotion.easing,
            builder: (context, t, child) => Opacity(
              opacity: t.clamp(0, 1),
              child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
            ),
            child: RepaintBoundary(
              key: cardKey,
              child: StyleDnaCard(result: result),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          HeroButton(
            label: l10n.quizShare,
            icon: Icons.ios_share_rounded,
            onPressed: onShare,
          ),
          const SizedBox(height: AppSpace.md),
          GhostButton(
            label: l10n.quizSave,
            icon: Icons.bookmark_added_outlined,
            onPressed: onSave,
          ),
          const SizedBox(height: AppSpace.sm),
          TextButton.icon(
            onPressed: onRetake,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.quizRetake),
          ),
        ],
      ),
    );
  }
}
