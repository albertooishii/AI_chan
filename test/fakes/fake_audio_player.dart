import 'dart:async';
import 'package:ai_chan/shared/infrastructure/audio/audio_playback.dart';

class FakeAudioPlayer implements AudioPlayback {
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
  Future<void> play(dynamic source) async {
    // simulate short playback then complete
    // Optionally emit a duration and a position progression for consumers
    Future.delayed(const Duration(milliseconds: 5), () {
      try {
        _durationController.add(const Duration(milliseconds: 40));
      } catch (_) {}
    });
    Future.delayed(const Duration(milliseconds: 20), () {
      try {
        _positionController.add(const Duration(milliseconds: 40));
        _completeController.add(null);
      } catch (_) {}
    });
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    try {
      _completeController.close();
      _durationController.close();
      _positionController.close();
    } catch (_) {}
  }

  @override
  Future<void> setReleaseMode(dynamic mode) async {}
}
