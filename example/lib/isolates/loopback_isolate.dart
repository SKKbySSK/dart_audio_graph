import 'dart:async';

import 'package:coast_audio/coast_audio.dart';
import 'package:coast_audio/experimental.dart';

enum LoopbackHostRequest {
  start,
  stop,
  stats,
}

final class LoopbackWorkerRequest {
  const LoopbackWorkerRequest();
}

class LoopbackStatsResponse {
  const LoopbackStatsResponse({
    required this.inputStability,
    required this.outputStability,
    required this.latency,
  });
  final double inputStability;
  final double outputStability;
  final AudioTime latency;
}

class LoopbackInitialMessage {
  const LoopbackInitialMessage({
    required this.backend,
    required this.inputDeviceId,
    required this.outputDeviceId,
  });
  final AudioDeviceBackend backend;
  final AudioDeviceId? inputDeviceId;
  final AudioDeviceId? outputDeviceId;
}

class LoopbackIsolateHost extends AudioIsolateHost<LoopbackInitialMessage, LoopbackHostRequest, LoopbackWorkerRequest> {
  Future<void> start() {
    return request(LoopbackHostRequest.start);
  }

  Future<void> stop() {
    return request(LoopbackHostRequest.stop);
  }

  Future<LoopbackStatsResponse?> stats() {
    return request(LoopbackHostRequest.stats);
  }

  @override
  AudioIsolateWorkerInitializer<LoopbackInitialMessage, LoopbackHostRequest, LoopbackWorkerRequest> get workerInitializer => LoopbackIsolateWorker.new;
}

class LoopbackIsolateWorker extends AudioIsolateWorker<LoopbackInitialMessage, LoopbackHostRequest, LoopbackWorkerRequest> {
  LoopbackIsolateWorker(super.messenger);
  final bufferFrameSize = 1024;
  final format = const AudioFormat(sampleRate: 48000, channels: 2, sampleFormat: SampleFormat.int16);

  late final CaptureNode capture;
  late final PlaybackNode playback;

  // Prepare the audio clock with a tick interval of 10ms.
  late final clock = AudioIntervalClock(const AudioTime(10 / 1000));

  @override
  FutureOr<void> setup(dynamic initialMessage) {
    final message = initialMessage as LoopbackInitialMessage;
    final context = AudioDeviceContext(backends: [message.backend]);

    // Prepare the capture and playback devices.
    capture = CaptureNode(
      device: context.createCaptureDevice(
        format: format,
        bufferFrameSize: bufferFrameSize,
        deviceId: message.inputDeviceId,
      ),
    );
    playback = PlaybackNode(
      device: context.createPlaybackDevice(
        format: format,
        bufferFrameSize: bufferFrameSize,
        deviceId: message.outputDeviceId,
      ),
    );

    capture.outputBus.connect(playback.inputBus);

    setRequestHandler(_handleRequest);
  }

  FutureOr<dynamic> _handleRequest(LoopbackHostRequest request) async {
    switch (request) {
      case LoopbackHostRequest.start:
        // Start the audio devices and the clock.
        capture.device.start();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        playback.device.start();

        // Start the clock and read from the capture device and write to the playback device every tick(10ms).
        clock.runWithBuffer(
          frames: AllocatedAudioFrames(length: bufferFrameSize, format: format),
          onTick: (clock, buffer) {
            playback.outputBus.read(buffer);
            return capture.device.isStarted;
          },
        );
      case LoopbackHostRequest.stop:
        clock.stop();
        capture.device.stop();
        playback.device.stop();
      case LoopbackHostRequest.stats:
        final inputStability = capture.device.availableWriteFrames / bufferFrameSize;
        final outputStability = playback.device.availableReadFrames / bufferFrameSize;
        return LoopbackStatsResponse(
          inputStability: inputStability,
          outputStability: outputStability,
          latency: AudioTime.fromFrames(capture.device.availableReadFrames + playback.device.availableReadFrames, format: format),
        );
    }
  }

  @override
  FutureOr<void> shutdown(AudioIsolateShutdownReason reason, Object? e, StackTrace? stackTrace) {
    clock.stop();
  }
}
