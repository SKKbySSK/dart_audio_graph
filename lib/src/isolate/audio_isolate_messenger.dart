part of 'audio_isolate.dart';

typedef AudioIsolateRequestHandler<TRequest, TResponse> = FutureOr<TResponse> Function(TRequest request);

class AudioIsolateHostMessenger<TWorkerRequestPayload> {
  AudioIsolateHostMessenger({Map<Type, AudioIsolateRequestHandler<TWorkerRequestPayload, dynamic>>? handlers}) {
    _handlers.addAll(handlers ?? {});
    _requestSubscription = _requestStream.listen((request) async {
      try {
        await _handleRequest(request);
      } catch (e, stackTrace) {
        assert(false, 'Error occured while handling worker request: $request\n$e\n$stackTrace');
      }
    });
  }

  final _receivePort = ReceivePort();
  SendPort? _sendPort;
  final _handlers = <Type, AudioIsolateRequestHandler<TWorkerRequestPayload, dynamic>>{};

  SendPort get _workerToHostSendPort => _receivePort.sendPort;

  StreamSubscription<AudioIsolateWorkerRequest>? _requestSubscription;

  late final _message = _receivePort.where((r) => r is AudioIsolateWorkerMessage).cast<AudioIsolateWorkerMessage>().asBroadcastStream();

  late final _requestStream = _message.where((r) => r is AudioIsolateWorkerRequest<TWorkerRequestPayload>).cast<AudioIsolateWorkerRequest<TWorkerRequestPayload>>().asBroadcastStream();

  void _attach(SendPort sendPort) {
    _sendPort = sendPort;
  }

  void _detach() {
    _sendPort = null;
  }

  void setRequestHandler<TRequest extends TWorkerRequestPayload, TResponse>(AudioIsolateRequestHandler<TRequest, TResponse> handler) {
    _handlers[TRequest] = (req) => handler(req as TRequest);
  }

  Future<TResponse> request<TRequest, TResponse>(TRequest payload) async {
    final sendPort = _sendPort;
    if (sendPort == null) {
      throw StateError('Messenger is not attached to an worker');
    }

    final request = AudioIsolateHostRequest(payload);
    final responseFuture = _message.firstWhere((r) => r is AudioIsolateWorkerResponse && r.requestId == request.id);
    sendPort.send(request);

    final response = await responseFuture as AudioIsolateWorkerResponse;

    switch (response) {
      case AudioIsolateWorkerSuccessResponse():
        if (response.payload is TResponse) {
          return response.payload as TResponse;
        } else {
          throw StateError('Unexpected response type: ${response.payload.runtimeType}');
        }
      case AudioIsolateWorkerFailedResponse():
        return Future.error(response.exception, response.stackTrace);
    }
  }

  void requestShutdown() {
    final sendPort = _sendPort;
    if (sendPort == null) {
      throw StateError('Messenger is not attached to an worker');
    }

    sendPort.send(const AudioIsolateShutdownRequest());
  }

  Future<dynamic> _handleRequest(AudioIsolateWorkerRequest<TWorkerRequestPayload> request) async {
    final sendPort = _sendPort;
    if (sendPort == null) {
      throw StateError('Messenger is not attached to an host');
    }

    final handler = _handlers[request.payload.runtimeType];
    if (handler == null) {
      sendPort.send(AudioIsolateHostFailedResponse(request.id, UnsupportedError('No handler for request type: ${request.payload.runtimeType}'), StackTrace.current));
      return;
    }

    try {
      final response = await handler(request.payload);
      sendPort.send(AudioIsolateHostSuccessResponse(request.id, response));
    } catch (e, stack) {
      sendPort.send(AudioIsolateHostFailedResponse(request.id, e, stack));
    }
  }

  void _close() {
    _detach();
    _receivePort.close();
    _handlers.clear();

    _requestSubscription?.cancel();
    _requestSubscription = null;
  }
}

class AudioIsolateWorkerMessenger<THostRequestPayload> {
  AudioIsolateWorkerMessenger() {
    _requestSubscription = _requestStream.listen((request) async {
      try {
        await _handleRequest(request);
      } catch (e, stackTrace) {
        assert(false, 'Error occured while handling host request: $request\n$e\n$stackTrace');
      }
    });
  }

  final _receivePort = ReceivePort();
  SendPort? _sendPort;
  final _handlers = <Type, AudioIsolateRequestHandler<THostRequestPayload, dynamic>>{};

  final _shutdownCompleter = Completer<AudioIsolateShutdownReason>();

  StreamSubscription<AudioIsolateHostRequest>? _requestSubscription;

  SendPort get _hostToWorkerSendPort => _receivePort.sendPort;

  late final _message = _receivePort.where((r) => r is AudioIsolateHostMessage).cast<AudioIsolateHostMessage>().asBroadcastStream();

  late final _requestStream = _message.where((r) => r is AudioIsolateHostRequest<THostRequestPayload>).cast<AudioIsolateHostRequest<THostRequestPayload>>().asBroadcastStream();

  void _attach(SendPort sendPort) {
    _sendPort = sendPort;
  }

  void _detach() {
    _sendPort = null;
  }

  void setRequestHandler<TRequest extends THostRequestPayload, TResponse>(AudioIsolateRequestHandler<TRequest, TResponse> handler) {
    _handlers[TRequest] = (req) => handler(req as TRequest);
  }

  Future<TResponse> request<TRequest, TResponse>(TRequest payload) async {
    final sendPort = _sendPort;
    if (sendPort == null) {
      throw StateError('Messenger is not attached to an worker');
    }

    final request = AudioIsolateWorkerRequest(payload);
    final responseFuture = _message.firstWhere((r) => r is AudioIsolateHostResponse && r.requestId == request.id);
    sendPort.send(request);

    try {
      final response = await responseFuture as AudioIsolateHostResponse;

      switch (response) {
        case AudioIsolateHostSuccessResponse():
          if (response.payload is TResponse) {
            return response.payload as TResponse;
          } else {
            return Future.error(StateError('Unexpected response type: ${response.payload.runtimeType}'));
          }
        case AudioIsolateHostFailedResponse():
          return Future.error(response.exception, response.stackTrace);
      }
    } catch (e, stackTrace) {
      return Future.error(e, stackTrace);
    }
  }

  void _onShutdownRequested(AudioIsolateShutdownRequest request) {
    _shutdownCompleter.complete(AudioIsolateShutdownReason.hostRequested);
  }

  void _onWorkerFinished() {
    _shutdownCompleter.complete(AudioIsolateShutdownReason.workerFinished);
  }

  Future<dynamic> _handleRequest(AudioIsolateHostRequest<THostRequestPayload> request) async {
    final sendPort = _sendPort;
    if (sendPort == null) {
      throw StateError('Messenger is not attached to an host');
    }

    final handler = _handlers[request.payload.runtimeType];
    if (handler == null) {
      sendPort.send(AudioIsolateWorkerFailedResponse(request.id, UnsupportedError('No handler for request type: ${request.payload.runtimeType}'), StackTrace.current));
      return;
    }

    try {
      final response = await handler(request.payload);
      sendPort.send(AudioIsolateWorkerSuccessResponse(request.id, response));
    } catch (e, stack) {
      sendPort.send(AudioIsolateWorkerFailedResponse(request.id, e, stack));
      _shutdownCompleter.completeError(e, stack);
    }
  }

  Future<void> listenShutdown({FutureOr<void> Function(AudioIsolateShutdownReason reason, Object? e, StackTrace? stackTrace)? onShutdown}) async {
    try {
      final reason = await _shutdownCompleter.future;
      await onShutdown?.call(reason, null, null);
    } catch (e, stack) {
      await onShutdown?.call(AudioIsolateShutdownReason.exception, e, stack);
    } finally {
      await _requestSubscription?.cancel();
      _requestSubscription = null;
    }
  }

  void _close() {
    _detach();
    _receivePort.close();
    _handlers.clear();

    _requestSubscription?.cancel();
    _requestSubscription = null;
  }
}
