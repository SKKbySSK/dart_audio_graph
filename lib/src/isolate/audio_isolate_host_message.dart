part of 'audio_isolate.dart';

sealed class AudioIsolateHostMessage {
  const AudioIsolateHostMessage();
}

class AudioIsolateHostRequest<TPayload> extends AudioIsolateHostMessage {
  static var _id = 0;

  static int _getId() {
    return _id++;
  }

  AudioIsolateHostRequest(this.payload) : id = _getId();
  final int id;
  final TPayload payload;
}

class AudioIsolateRunRequest<TInitialMessage> extends AudioIsolateHostMessage {
  const AudioIsolateRunRequest({
    required this.initialMessage,
    required this.worker,
  });
  final TInitialMessage? initialMessage;
  final FutureOr<void> Function(TInitialMessage? initialMessage, AudioIsolateWorkerMessenger messenger) worker;
}

class AudioIsolateShutdownRequest extends AudioIsolateHostMessage {
  const AudioIsolateShutdownRequest();
}

sealed class AudioIsolateHostResponse extends AudioIsolateHostMessage {
  static var _id = 0;

  static int _getId() {
    return _id++;
  }

  AudioIsolateHostResponse(this.requestId) : id = _getId();
  final int id;
  final int requestId;
}

class AudioIsolateHostSuccessResponse extends AudioIsolateHostResponse {
  AudioIsolateHostSuccessResponse(super.requestId, this.payload);
  final dynamic payload;
}

class AudioIsolateHostFailedResponse extends AudioIsolateHostResponse {
  AudioIsolateHostFailedResponse(super.requestId, this.exception, this.stackTrace);
  final Object exception;
  final StackTrace stackTrace;
}
