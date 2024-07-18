import 'dart:async';
import 'dart:isolate';

import 'package:coast_audio/coast_audio.dart';

part 'audio_isolate_host_message.dart';
part 'audio_isolate_messenger.dart';
part 'audio_isolate_worker_message.dart';

Future<void> _audioIsolateRunner<TInitialMessage, THostReuqestPayload>(SendPort sendPort) async {
  final messenger = AudioIsolateWorkerMessenger<THostReuqestPayload>().._attach(sendPort);
  sendPort.send(AudioIsolateLaunchedResponse(sendPort: messenger._hostToWorkerSendPort));

  final req = (await messenger._message.firstWhere((r) => r is AudioIsolateRunRequest<TInitialMessage>)) as AudioIsolateRunRequest<TInitialMessage>;

  var isShutdownRequested = false;

  Future<void> runWorker() async {
    try {
      await req.worker(req.initialMessage, messenger);
      if (!isShutdownRequested) {
        messenger._onWorkerFinished();
        sendPort.send(const AudioIsolateShutdownResponse(reason: AudioIsolateShutdownReason.workerFinished));
      }
    } catch (e, s) {
      messenger._hostToWorkerSendPort.send(AudioIsolateWorkerFailedResponse(0, e, s));
      sendPort.send(
        AudioIsolateShutdownResponse(
          reason: AudioIsolateShutdownReason.exception,
          exception: e,
          stackTrace: s,
        ),
      );
    }
  }

  Future<void> gracefulStop() async {
    try {
      final request = await messenger._message.firstWhere((r) => r is AudioIsolateShutdownRequest);
      messenger._onShutdownRequested(request as AudioIsolateShutdownRequest);
      isShutdownRequested = true;

      sendPort.send(const AudioIsolateShutdownResponse(reason: AudioIsolateShutdownReason.hostRequested));
    } on StateError {
      return;
    }
  }

  try {
    await Future.wait<void>([
      gracefulStop(),
      runWorker(),
    ]);
  } finally {
    messenger._close();
    AudioResourceManager.disposeAll();
    Isolate.exit();
  }
}

final class AudioIsolate<TInitialMessage, TWorkerRequestPayload> {
  AudioIsolate(this._worker) {
    _messenger._message.listen(_messengerLifecycleListener);
  }

  final FutureOr<void> Function(TInitialMessage? initialMessage, AudioIsolateWorkerMessenger messenger) _worker;

  var _messenger = AudioIsolateHostMessenger<TWorkerRequestPayload>();

  _AudioIsolateSession<TInitialMessage>? _session;

  bool get isLaunched => _session != null;

  Future<AudioIsolateLaunchedResponse> launch({TInitialMessage? initialMessage}) async {
    if (_session != null) {
      throw StateError('AudioIsolate is already running');
    }

    final isolate = await Isolate.spawn(
      _audioIsolateRunner,
      _messenger._workerToHostSendPort,
      paused: true,
    );
    final session = _AudioIsolateSession(initialMessage, isolate);
    _session = session;

    isolate.resume(isolate.pauseCapability!);

    return session.launchCompleter.future;
  }

  void setRequestHandler<TRequest extends TWorkerRequestPayload, TResponse>(AudioIsolateRequestHandler<TRequest, TResponse> handler) {
    _messenger.setRequestHandler(handler);
  }

  Future<AudioIsolateShutdownResponse> attach() {
    final session = _session;
    if (session == null) {
      throw StateError('AudioIsolate is not running');
    }

    return session.lifecycleCompleter.future;
  }

  Future<TResponse?> request<TResponse>(dynamic payload) async {
    if (_session == null) {
      throw StateError('AudioIsolate is not running');
    }

    return _messenger.request(payload);
  }

  Future<AudioIsolateShutdownResponse> shutdown() async {
    final session = _session;
    if (session == null) {
      throw StateError('AudioIsolate is not running');
    }

    _messenger.requestShutdown();
    return session.shutdownCompleter.future;
  }

  void _messengerLifecycleListener(AudioIsolateWorkerMessage response) async {
    final session = _session;
    if (session == null) {
      throw StateError('Unexpected Audio Isolate State');
    }

    switch (response) {
      case AudioIsolateLaunchedResponse():
        _messenger._attach(response._sendPort);
        response._sendPort.send(
          AudioIsolateRunRequest<TInitialMessage>(
            initialMessage: session.initialMessage,
            worker: _worker,
          ),
        );
        session.launchCompleter.complete(response);
      case AudioIsolateShutdownResponse():
        _session = null;
        final lastHandlers = Map<Type, AudioIsolateRequestHandler>.from(_messenger._handlers);
        _messenger._close();

        _messenger = AudioIsolateHostMessenger(handlers: lastHandlers);
        _messenger._message.listen(_messengerLifecycleListener);

        if (response.exception != null && !session.launchCompleter.isCompleted) {
          session.launchCompleter.completeError(response.exception!, response.stackTrace!);
        }

        if (response.exception == null) {
          session.lifecycleCompleter.complete(response);
        } else {
          session.lifecycleCompleter.completeError(response.exception!, response.stackTrace!);
        }

        session.shutdownCompleter.complete(response);
      case AudioIsolateWorkerRequest():
      case AudioIsolateWorkerResponse():
        break;
    }
  }
}

class _AudioIsolateSession<TInitialMessage> {
  _AudioIsolateSession(this.initialMessage, this.isolate);
  final TInitialMessage? initialMessage;
  final Isolate isolate;
  final Completer<AudioIsolateLaunchedResponse> launchCompleter = Completer();
  final Completer<AudioIsolateShutdownResponse> lifecycleCompleter = Completer();
  final Completer<AudioIsolateShutdownResponse> shutdownCompleter = Completer();
}
