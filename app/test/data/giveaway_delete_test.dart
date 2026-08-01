/// Owner-only permanent deletion of a giveaway.
///
/// The feature existed on the server (`DELETE /v1/giveaways/{id}`, 204) and was
/// simply never built in the client, which is why an owner could close a listing
/// but never remove it. These tests pin the contract that matters most for a
/// destructive action: the call shape, and that a FAILED delete leaves the post
/// alone rather than optimistically dropping it.
library;

import 'dart:typed_data';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/repositories/giveaway_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what was called and replays a scripted outcome. A real Dio would make
/// this a network test; the point here is the request the repository issues.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.status, {this.throwOn});

  final int status;
  final DioExceptionType? throwOn;
  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.path}');
    if (throwOn != null) {
      throw DioException(requestOptions: options, type: throwOn!);
    }
    return ResponseBody.fromString('', status);
  }

  @override
  void close({bool force = false}) {}
}

GiveawayRepository _repo(_RecordingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
  dio.httpClientAdapter = adapter;
  return GiveawayRepository(dio);
}

void main() {
  group('GiveawayRepository.delete', () {
    test('issues DELETE /v1/giveaways/{id} exactly once', () async {
      final adapter = _RecordingAdapter(204);
      await _repo(adapter).delete('g-123');
      expect(adapter.calls, ['DELETE /v1/giveaways/g-123']);
    });

    test('204 No Content is a success, not an error', () async {
      final adapter = _RecordingAdapter(204);
      await expectLater(_repo(adapter).delete('g-123'), completes);
    });

    test(
      '404 surfaces as ApiException — the post must NOT be dropped locally',
      () async {
        // A non-owner gets 404, deliberately indistinguishable from "missing", so
        // this is also the forged-delete case. Either way the caller must treat it
        // as a failure and leave the listing on screen.
        final adapter = _RecordingAdapter(404);
        await expectLater(
          _repo(adapter).delete('someone-elses'),
          throwsA(isA<ApiException>()),
        );
        expect(adapter.calls, ['DELETE /v1/giveaways/someone-elses']);
      },
    );

    test('server error surfaces as ApiException', () async {
      final adapter = _RecordingAdapter(500);
      await expectLater(
        _repo(adapter).delete('g-123'),
        throwsA(isA<ApiException>()),
      );
    });

    test(
      'network failure surfaces as ApiException, never a raw DioException',
      () async {
        final adapter = _RecordingAdapter(
          200,
          throwOn: DioExceptionType.connectionError,
        );
        await expectLater(
          _repo(adapter).delete('g-123'),
          throwsA(isA<ApiException>()),
        );
      },
    );

    test(
      'delete is distinct from closing — it does not PATCH a status',
      () async {
        // Closing keeps the post and is reversible with Reopen; deleting removes
        // it. Conflating the two is how a listing gets destroyed by accident.
        final adapter = _RecordingAdapter(204);
        await _repo(adapter).delete('g-123');
        expect(adapter.calls.single.startsWith('DELETE'), isTrue);
        expect(adapter.calls.any((c) => c.startsWith('PATCH')), isFalse);
      },
    );
  });
}
