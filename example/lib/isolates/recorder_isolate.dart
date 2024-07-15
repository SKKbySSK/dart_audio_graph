import 'dart:io';

import 'package:coast_audio/coast_audio.dart';
import 'package:coast_audio/experimental.dart';

final class RecorderHostRequest {
  const RecorderHostRequest();
}

class _RecorderInitialMessage {
  const _RecorderInitialMessage({
    required this.backend,
    required this.inputDeviceId,
    required this.path,
  });
  final AudioDeviceBackend backend;
  final AudioDeviceId? inputDeviceId;
  final String path;
}

/// A recorder isolate that captures audio from an input device and writes it to a wav file.
class RecorderIsolate {
  RecorderIsolate();
  final _isolate = AudioIsolate<_RecorderInitialMessage, RecorderHostRequest>(_worker);

  bool get isLaunched => _isolate.isLaunched;

  Future<void> start({
    required AudioDeviceBackend backend,
    required AudioDeviceId? inputDeviceId,
    required String path,
  }) async {
    await _isolate.launch(
      initialMessage: _RecorderInitialMessage(
        backend: backend,
        inputDeviceId: inputDeviceId,
        path: path,
      ),
    );
  }

  Future<void> stop() {
    return _isolate.shutdown();
  }

  // The worker function that runs in the isolate.
  static Future<void> _worker(_RecorderInitialMessage? initialMessage, AudioIsolateWorkerMessenger messenger) async {
    AudioResourceManager.isDisposeLogEnabled = true;

    final message = initialMessage as _RecorderInitialMessage;

    // Prepare the audio format and buffer, audio device and encoder.
    const format = AudioFormat(sampleRate: 48000, channels: 2, sampleFormat: SampleFormat.int16);

    final context = AudioDeviceContext(backends: [message.backend]);
    final device = context.createCaptureDevice(
      format: format,
      bufferFrameSize: const AudioTime(0.4).computeFrames(format),
      deviceId: message.inputDeviceId,
    );

    final dataSource = AudioFileDataSource(file: File(message.path), mode: FileMode.write);
    final encoder = WavAudioEncoder(dataSource: dataSource, inputFormat: format);
    final clock = AudioIntervalClock(const AudioTime(0.2));
    final bufferFrames = AllocatedAudioFrames(length: device.bufferFrameSize, format: format);

    // Start the audio device, clock and encoder.
    encoder.start();
    device.start();

    clock.start(
      onTick: (_) {
        // Read the audio data from the device and encode it.
        bufferFrames.acquireBuffer((buffer) {
          final result = device.read(buffer);
          encoder.encode(buffer.limit(result.framesRead));
        });
      },
    );

    await messenger.listenShutdown(
      onShutdown: (reason, e, stackTrace) async {
        device.stop();
        clock.stop();

        // Finalize the encoder and close the data source.
        // If you don't finalize the encoder, the wav file will be corrupted.
        encoder.finalize();
      },
    );
  }
}
