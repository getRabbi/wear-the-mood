import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/quiz.dart';
import 'package:app/features/quiz/style_dna_card.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('quiz models', () {
    test('ActiveQuiz.fromJson maps questions + options (snake_case)', () {
      final quiz = ActiveQuiz.fromJson({
        'id': 'q1',
        'slug': 'style-dna',
        'title': 'Style DNA',
        'description': 'desc',
        'questions': [
          {
            'id': 'qq1',
            'prompt': 'Pick a vibe',
            'options': [
              {'key': 'minimal', 'label': 'Clean'},
              {'key': 'bold', 'label': 'Vibrant', 'image_url': 'https://x'},
            ],
          },
        ],
      });
      expect(quiz.title, 'Style DNA');
      expect(quiz.questions.single.options.length, 2);
      expect(quiz.questions.single.options.first.key, 'minimal');
      expect(quiz.questions.single.options[1].imageUrl, 'https://x');
    });

    test('QuizResult.fromJson maps the nested StyleResult', () {
      final result = QuizResult.fromJson({
        'id': 'r1',
        'created_at': '2026-01-01T00:00:00Z',
        'result': {
          'title': 'Minimal · Earthy · Classic',
          'keywords': ['minimal', 'earthy', 'classic'],
          'description': 'Your Style DNA blends ...',
          'palette': ['#9E9E9E', '#8B6B4A', '#1A1A1A'],
        },
      });
      expect(result.result.keywords, ['minimal', 'earthy', 'classic']);
      expect(result.result.palette.length, 3);
    });
  });

  testWidgets('StyleDnaCard renders the title, keywords and description',
      (tester) async {
    const result = StyleResult(
      title: 'Minimal · Earthy',
      keywords: ['minimal', 'earthy'],
      description: 'Your Style DNA blends clean lines and warm tones.',
      palette: ['#9E9E9E', '#8B6B4A'],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: StyleDnaCard(result: result)),
      ),
    );

    expect(find.text('Minimal · Earthy'), findsOneWidget);
    expect(find.text('#minimal'), findsOneWidget);
    expect(find.textContaining('clean lines'), findsOneWidget);
  });
}
