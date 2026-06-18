import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/poll.dart';
import 'package:app/data/models/post.dart';

void main() {
  test('Poll.fromJson maps snake_case keys and computes vote state', () {
    final poll = Poll.fromJson({
      'id': 'p1',
      'question': 'Which fit?',
      'options': [
        {'index': 0, 'label': 'A', 'votes': 3},
        {'index': 1, 'label': 'B', 'votes': 1},
      ],
      'total_votes': 4,
      'my_choice': 0,
      'closes_at': null,
      'is_closed': false,
    });

    expect(poll.question, 'Which fit?');
    expect(poll.options.length, 2);
    expect(poll.options.first.votes, 3);
    expect(poll.totalVotes, 4);
    expect(poll.myChoice, 0);
    expect(poll.hasVoted, isTrue);
    expect(poll.showResults, isTrue); // voted → results
  });

  test('an open, unvoted poll shows options; a closed one shows results', () {
    final open = Poll.fromJson({
      'id': 'p',
      'question': 'q',
      'options': [
        {'index': 0, 'label': 'A'},
        {'index': 1, 'label': 'B'},
      ],
      'total_votes': 0,
      'my_choice': null,
      'is_closed': false,
    });
    expect(open.hasVoted, isFalse);
    expect(open.showResults, isFalse);
    expect(open.copyWith(isClosed: true).showResults, isTrue);
  });

  test('Post.fromJson parses a nested poll and is null when absent', () {
    final withPoll = Post.fromJson({
      'id': '1',
      'user_id': 'u',
      'created_at': '2026-01-01T00:00:00Z',
      'poll': {
        'id': 'p',
        'question': 'q',
        'options': [
          {'index': 0, 'label': 'A'},
          {'index': 1, 'label': 'B'},
        ],
        'total_votes': 0,
        'is_closed': false,
      },
    });
    expect(withPoll.poll, isNotNull);
    expect(withPoll.poll!.options.length, 2);

    final noPoll = Post.fromJson({
      'id': '2',
      'user_id': 'u',
      'created_at': '2026-01-01T00:00:00Z',
    });
    expect(noPoll.poll, isNull);
  });
}
