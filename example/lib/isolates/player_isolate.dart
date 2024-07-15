import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:coast_audio/coast_audio.dart';
import 'package:coast_audio/experimental.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

sealed class PlayerHostRequest {
  const PlayerHostRequest();
}

class PlayerHostRequestStart extends PlayerHostRequest {
  const PlayerHostRequestStart();
}

class PlayerHostRequestPause extends PlayerHostRequest {
  const PlayerHostRequestPause();
}

class PlayerHostRequestSeek extends PlayerHostRequest {
  const PlayerHostRequestSeek({
    required this.position,
  });
  final AudioTime position;
}

class PlayerHostRequestSetVolume extends PlayerHostRequest {
  const PlayerHostRequestSetVolume({
    required this.volume,
  });
  final double volume;
}

class PlayerHostRequestGetPosition extends PlayerHostRequest {
  const PlayerHostRequestGetPosition();
}

class PlayerHostRequestGetState extends PlayerHostRequest {
  const PlayerHostRequestGetState();
}

class PlayerStateResponse extends Equatable {
  const PlayerStateResponse({
    required this.isPlaying,
    required this.outputFormat,
  });
  final bool isPlaying;
  final AudioFormat outputFormat;

  @override
  List<Object?> get props => [isPlaying, outputFormat.sampleRate, outputFormat.channels, outputFormat.sampleFormat];
}

class PlayerPositionResponse extends Equatable {
  const PlayerPositionResponse({
    required this.position,
    required this.duration,
  });
  final AudioTime position;
  final AudioTime duration;

  @override
  List<Object?> get props => [position, duration];
}

class _PlayerInitialMessage {
  const _PlayerInitialMessage({
    required this.backend,
    required this.outputDeviceId,
    required this.path,
    required this.content,
  });
  final AudioDeviceBackend backend;
  final AudioDeviceId? outputDeviceId;
  final String? path;
  final Uint8List? content;
}

/// A player isolate that plays audio from a file or buffer.
class PlayerIsolate {
  PlayerIsolate();
  final _isolate = AudioIsolate<_PlayerInitialMessage, PlayerHostRequest>(_worker);

  bool get isLaunched => _isolate.isLaunched;

  Future<void> launch({
    required AudioDeviceBackend backend,
    required AudioDeviceId? outputDeviceId,
    required String? path,
    required Uint8List? content,
  }) async {
    await _isolate.launch(
      initialMessage: _PlayerInitialMessage(
        backend: backend,
        outputDeviceId: outputDeviceId,
        path: path,
        content: content,
      ),
    );
  }

  Future<void> attach() {
    return _isolate.attach();
  }

  Future<void> shutdown() {
    return _isolate.shutdown();
  }

  Future<void> play() {
    return _isolate.request(const PlayerHostRequestStart());
  }

  Future<void> pause() {
    return _isolate.request(const PlayerHostRequestPause());
  }

  Future<PlayerPositionResponse?> seek(AudioTime position) {
    return _isolate.request(PlayerHostRequestSeek(position: position));
  }

  Future<void> setVolume(double volume) {
    return _isolate.request(PlayerHostRequestSetVolume(volume: volume));
  }

  Future<PlayerStateResponse?> getState() {
    return _isolate.request(const PlayerHostRequestGetState());
  }

  Future<PlayerPositionResponse?> getPosition() {
    return _isolate.request(const PlayerHostRequestGetPosition());
  }

  // The worker function used to initialize the audio player in the isolate
  static Future<void> _worker(_PlayerInitialMessage? initialMessage, AudioIsolateWorkerMessenger<dynamic> messenger) async {
    AudioResourceManager.isDisposeLogEnabled = true;

    final message = initialMessage as _PlayerInitialMessage;

    // Initialize the audio player with the specified file or buffer
    final AudioInputDataSource dataSource;
    if (message.path != null) {
      dataSource = AudioFileDataSource(file: File(message.path!), mode: FileMode.read);
    } else {
      dataSource = AudioMemoryDataSource(buffer: message.content!);
    }

    final player = AudioPlayer.findDecoder(
      backend: message.backend,
      dataSource: dataSource,
      deviceId: message.outputDeviceId,
    );

    messenger.setRequestHandler<PlayerHostRequestStart, void>((_) => player.play());
    messenger.setRequestHandler<PlayerHostRequestPause, void>((_) => player.pause());
    messenger.setRequestHandler<PlayerHostRequestSetVolume, void>((r) => player.volume = r.volume);
    messenger.setRequestHandler<PlayerHostRequestGetState, PlayerStateResponse>((r) => player.getState());
    messenger.setRequestHandler<PlayerHostRequestGetPosition, PlayerPositionResponse>((r) => player.getPosition());
    messenger.setRequestHandler<PlayerHostRequestSeek, PlayerPositionResponse>(
      (r) {
        player.position = r.position;
        return player.getPosition();
      },
    );

    // Wait for the isolate to be shutdown
    await messenger.listenShutdown();
  }
}

class AudioPlayer {
  AudioPlayer({
    required this.context,
    required AudioDecoder decoder,
    this.bufferDuration = const AudioTime(0.5),
    AudioDeviceId? initialDeviceId,
  })  : _decoderNode = DecoderNode(decoder: decoder),
        _playbackNode = PlaybackNode(
          device: context.createPlaybackDevice(
            format: decoder.outputFormat,
            bufferFrameSize: bufferDuration.computeFrames(decoder.outputFormat),
            deviceId: initialDeviceId,
          ),
        ) {
    _decoderNode.outputBus.connect(_playbackNode.inputBus);
    _playbackNode.device.notification.listen((notification) {
      print('[AudioPlayer#${_playbackNode.device.resourceId}] Notification(type: ${notification.type.name}, state: ${notification.state.name})');
    });
  }

  factory AudioPlayer.findDecoder({
    required AudioDeviceBackend backend,
    required AudioInputDataSource dataSource,
    AudioDeviceId? deviceId,
  }) {
    // Find the decoder by trying to decode the audio data with different decoders
    AudioDecoder decoder;
    try {
      decoder = WavAudioDecoder(dataSource: dataSource);
    } on Exception catch (_) {
      try {
        decoder = MaAudioDecoder(dataSource: dataSource, expectedSampleFormat: SampleFormat.float32);
      } on Exception catch (e) {
        throw Exception('Could not find the decoder.\nInner exception: $e');
      }
    }

    return AudioPlayer(
      context: AudioDeviceContext(backends: [backend]),
      decoder: decoder,
      initialDeviceId: deviceId,
    );
  }

  // The AudioDeviceContext is used to create the playback device on the specified backend(platform)
  final AudioDeviceContext context;

  final AudioTime bufferDuration;

  final DecoderNode _decoderNode;

  final PlaybackNode _playbackNode;

  bool get isPlaying => _playbackNode.device.isStarted;

  double get volume => _playbackNode.device.volume;

  set volume(double value) {
    _playbackNode.device.volume = value;
  }

  /// Get the current playback time
  AudioTime get position {
    return AudioTime.fromFrames(
      _decoderNode.decoder.cursorInFrames - _playbackNode.device.availableReadFrames,
      format: _decoderNode.decoder.outputFormat,
    );
  }

  /// Set the current playback time
  set position(AudioTime value) {
    // Set the cursor in the decoder to the specified position
    _decoderNode.decoder.cursorInFrames = value.computeFrames(_decoderNode.decoder.outputFormat);

    // Clear the playback device's buffer to prevent old audio data from being played
    _playbackNode.device.clearBuffer();
  }

  // Get the current playback state
  PlayerStateResponse getState() {
    return PlayerStateResponse(
      isPlaying: isPlaying,
      outputFormat: _decoderNode.decoder.outputFormat,
    );
  }

  PlayerPositionResponse getPosition() {
    return PlayerPositionResponse(
      position: position,
      duration: AudioTime.fromFrames(_decoderNode.decoder.lengthInFrames!, format: _decoderNode.decoder.outputFormat),
    );
  }

  void play() {
    if (isPlaying) {
      return;
    }

    _playbackNode.device.start();

    // runWithBuffer is a helper method that runs the specified callback with the audio buffer
    // This code will run the callback every 0.4 seconds and read the audio data from the decoder
    AudioIntervalClock(AudioTime(bufferDuration.seconds * 0.4)).runWithBuffer(
      frames: AllocatedAudioFrames(
        length: bufferDuration.computeFrames(_decoderNode.decoder.outputFormat),
        format: _decoderNode.decoder.outputFormat,
      ),
      onTick: (_, buffer) {
        final result = _playbackNode.outputBus.read(buffer);
        if (result.isEnd) {
          return false;
        }

        if (!_playbackNode.device.isStarted) {
          return false;
        }

        return true;
      },
    );
  }

  void pause() {
    _playbackNode.device.stop();
  }
}
