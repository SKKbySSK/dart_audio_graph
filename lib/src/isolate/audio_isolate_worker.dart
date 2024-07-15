import 'dart:async';

import 'package:coast_audio/experimental.dart';

abstract class AudioIsolateWorker<TInitialMessage, THostRequest, TWorkerRequest> {
  const AudioIsolateWorker(this._messenger);
  final AudioIsolateWorkerMessenger<dynamic> _messenger;

  FutureOr<void> setup(TInitialMessage initialMessage);

  void run() {}

  Future<THostResponse> request<THostResponse>(TWorkerRequest request) async {
    return await _messenger.request(request);
  }

  void setRequestHandler<TRequest extends THostRequest, TResponse>(AudioIsolateRequestHandler<TRequest, TResponse> handler) {
    _messenger.setRequestHandler(handler);
  }

  FutureOr<void> shutdown(AudioIsolateShutdownReason reason, Object? e, StackTrace? stackTrace) {}
}
