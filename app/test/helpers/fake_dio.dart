import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Minimal [HttpClientAdapter] that returns canned responses, so repository
/// tests run without a real network or extra mocking package.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  RequestOptions? lastRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return handler(options);
  }
}

ResponseBody jsonResponse(Object body, {int status = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

/// Builds a Dio wired to a [FakeAdapter] returning [response]; the adapter is
/// returned too so tests can inspect the captured request.
(Dio, FakeAdapter) fakeDio(ResponseBody Function(RequestOptions) handler) {
  final adapter = FakeAdapter(handler);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = adapter;
  return (dio, adapter);
}
