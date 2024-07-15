part of 'audio_isolate.dart';

sealed class AudioIsolateWorkerMessage {
  const AudioIsolateWorkerMessage();
}

class AudioIsolateWorkerRequest<TPayload> extends AudioIsolateWorkerMessage {
  static var _id = 0;

  static int _getId() {
    return _id++;
  }

  AudioIsolateWorkerRequest(this.payload) : id = _getId();
  final int id;
  final TPayload payload;
}

sealed class AudioIsolateWorkerResponse extends AudioIsolateWorkerMessage {
  static var _id = 0;

  static int _getId() {
    return _id++;
  }

  AudioIsolateWorkerResponse(this.requestId) : id = _getId();
  final int id;
  final int requestId;
}

class AudioIsolateWorkerSuccessResponse extends AudioIsolateWorkerResponse {
  AudioIsolateWorkerSuccessResponse(super.requestId, this.payload);
  final dynamic payload;
}

class AudioIsolateWorkerFailedResponse extends AudioIsolateWorkerResponse {
  AudioIsolateWorkerFailedResponse(super.requestId, this.exception, this.stackTrace);
  final Object exception;
  final StackTrace stackTrace;
}

final class AudioIsolateLaunchedResponse extends AudioIsolateWorkerMessage {
  const AudioIsolateLaunchedResponse({required this.sendPort});
  final SendPort sendPort;
}

final class AudioIsolateShutdownResponse extends AudioIsolateWorkerMessage {
  const AudioIsolateShutdownResponse({
    required this.reason,
    this.exception,
    this.stackTrace,
  });
  final AudioIsolateShutdownReason reason;
  final Object? exception;
  final StackTrace? stackTrace;
}

enum AudioIsolateShutdownReason {
  workerFinished,
  hostRequested,
  exception,
}
