import 'dart:async';

import 'package:coast_audio/experimental.dart';

typedef AudioIsolateWorkerInitializer<TInitialMessage, THostRequest, TWorkerRequest> = AudioIsolateWorker<TInitialMessage, THostRequest, TWorkerRequest> Function(AudioIsolateWorkerMessenger<THostRequest> messenger);

abstract class AudioIsolateHost<TInitialMessage, THostRequest, TWorkerRequest> {
  final _isolate = AudioIsolate(_audioIsolateWorkerEntryPoint);

  bool get isLaunched => _isolate.isLaunched;

  FutureOr<void> launch({
    required TInitialMessage initialMessage,
  }) async {
    await _isolate.launch(
      initialMessage: _AudioIsolateWorkerInitialMessage(
        initializer: workerInitializer,
        workerInitialMessage: initialMessage,
      ),
    );

    if (_isolate.isLaunched) {
      _isolate.attach().then((shutdownResponse) {
        onShutdown(shutdownResponse.reason, shutdownResponse.exception, shutdownResponse.stackTrace);
      });
    }
  }

  Future<TWorkerResponse> request<TWorkerResponse>(THostRequest request) async {
    return await _isolate.request(request);
  }

  void setRequestHandler<TRequest extends TWorkerRequest, TResponse>(AudioIsolateRequestHandler<TRequest, TResponse> handler) {
    _isolate.setRequestHandler(handler);
  }

  Future<void> shutdown() async {
    await _isolate.shutdown();
  }

  AudioIsolateWorkerInitializer<TInitialMessage, THostRequest, TWorkerRequest> get workerInitializer;

  void onShutdown(AudioIsolateShutdownReason reason, Object? e, StackTrace? stackTrace) {}
}

class _AudioIsolateWorkerInitialMessage {
  const _AudioIsolateWorkerInitialMessage({
    required this.initializer,
    this.workerInitialMessage,
  });
  final dynamic initializer;
  final dynamic workerInitialMessage;
}

Future<void> _audioIsolateWorkerEntryPoint<THostRequest, TWorkerRequest>(dynamic initialMessage, AudioIsolateWorkerMessenger<dynamic> messenger) async {
  final message = initialMessage as _AudioIsolateWorkerInitialMessage;
  final worker = Function.apply(message.initializer, [messenger]) as AudioIsolateWorker;

  await worker.setup(message.workerInitialMessage);
  messenger.endConfiguration();

  worker.run();

  await messenger.listenShutdown(
    onShutdown: (reason, e, stackTrace) {
      return worker.shutdown(reason, e, stackTrace);
    },
  );
}
