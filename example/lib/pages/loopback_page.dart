import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:coast_audio/coast_audio.dart';
import 'package:example/isolates/loopback_isolate.dart';
import 'package:example/models/audio_state.dart';
import 'package:flutter/material.dart';

class LoopbackPage extends StatefulWidget {
  const LoopbackPage({
    super.key,
    required this.audio,
  });
  final AudioStateConfigured audio;

  @override
  State<LoopbackPage> createState() => _LoopbackPageState();
}

class _LoopbackPageState extends State<LoopbackPage> {
  final loopbackIsolate = LoopbackIsolateHost();
  Timer? _timer;

  var _isStarted = false;
  var _stats = const LoopbackStatsResponse(
    inputStability: 0,
    outputStability: 0,
    latency: AudioTime(0),
  );

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    super.dispose();
    _timer?.cancel();
    loopbackIsolate.shutdown();
  }

  Future<void> _init() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker | AVAudioSessionCategoryOptions.allowBluetooth,
        ),
      );
      await session.setActive(true);
    }

    await loopbackIsolate.launch(
      initialMessage: LoopbackInitialMessage(
        backend: widget.audio.backend,
        inputDeviceId: widget.audio.inputDevice?.id,
        outputDeviceId: widget.audio.outputDevice?.id,
      ),
    );

    _timer = Timer.periodic(
      const Duration(milliseconds: 20),
      (timer) async {
        if (!loopbackIsolate.isLaunched) {
          return;
        }

        final stats = await loopbackIsolate.stats();
        if (!context.mounted) {
          return;
        }

        if (stats == null) {
          return;
        }

        setState(() => _stats = stats);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loopback'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isStarted)
              ElevatedButton.icon(
                onPressed: () {
                  loopbackIsolate.stop();
                  setState(() {
                    _isStarted = false;
                  });
                },
                label: const Text('Stop'),
                icon: const Icon(Icons.stop),
              ),
            if (!_isStarted)
              ElevatedButton.icon(
                onPressed: () {
                  loopbackIsolate.start();
                  setState(() {
                    _isStarted = true;
                  });
                },
                label: const Text('Start'),
                icon: const Icon(Icons.play_arrow),
              ),
            const SizedBox(height: 12),
            Text('Input Stability: ${(_stats.inputStability * 100).toStringAsFixed(1)}%'),
            Text('Output Stability: ${(_stats.outputStability * 100).toStringAsFixed(1)}%'),
            Text('Buffered Duration (Latency): ${(_stats.latency.seconds * 1000).toStringAsFixed(1)}ms'),
          ],
        ),
      ),
    );
  }
}
