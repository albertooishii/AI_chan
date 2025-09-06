import 'dart:async';
import 'dart:io';
import 'package:ai_chan/shared/infrastructure/audio/audio_playback.dart';

/// Minimal fake AudioPlayback for tests: no native plugins, simple streams.
class FakeAudioPlayback implements AudioPlayback {
  final _completeController = StreamController<void>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();

  @override
  Stream<void> get onPlayerComplete => _completeController.stream;

  @override
  Stream<Duration> get onDurationChanged => _durationController.stream;

  @override
  Stream<Duration> get onPositionChanged => _positionController.stream;

  @override
  Future<void> dispose() async {
    await _completeController.close();
    await _durationController.close();
    await _positionController.close();
  }

  @override
  Future<void> play(final dynamic source) async {
    // Simulate immediate duration/position and completion for local file sources
    try {
      if (source is String) {
        final f = File(source);
        if (f.existsSync()) {
          _durationController.add(const Duration(milliseconds: 500));
          _positionController.add(Duration.zero);
          // Simulate a short delay then complete
          Future.delayed(const Duration(milliseconds: 10), () {
            _positionController.add(const Duration(milliseconds: 500));
            _completeController.add(null);
          });
          return;
        }
      }
    } on Exception catch (_) {}
    // For non-file sources just emit complete
    Future.microtask(() {
      _completeController.add(null);
    });
  }

  @override
  Future<void> setReleaseMode(final mode) async {}

  @override
  Future<void> stop() async {
    // emit complete when stopped
    _completeController.add(null);
  }
}
