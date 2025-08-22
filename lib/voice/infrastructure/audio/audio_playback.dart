import 'dart:async';
import 'package:audioplayers/audioplayers.dart' as ap;

/// Abstraction over audio playback so production code can use the real
/// audioplayers implementation while tests inject a lightweight fake.
abstract class AudioPlayback {
  Stream<void> get onPlayerComplete;
  Stream<Duration> get onDurationChanged;
  Stream<Duration> get onPositionChanged;
  Future<void> play(dynamic source);
  Future<void> stop();
  Future<void> dispose();
  Future<void> setReleaseMode(dynamic mode);

  /// Helper to adapt either an existing [ap.AudioPlayer] or an [AudioPlayback]
  /// instance into an [AudioPlayback]. If [candidate] is null a new real
  /// [ap.AudioPlayer] wrapped will be returned.
  static AudioPlayback adapt(dynamic candidate) {
    if (candidate == null) return RealAudioPlayback(ap.AudioPlayer());
    if (candidate is AudioPlayback) return candidate;
    if (candidate is ap.AudioPlayer) return RealAudioPlayback(candidate);
    // Fallback: try to construct a real player
    return RealAudioPlayback(ap.AudioPlayer());
  }
}

class RealAudioPlayback implements AudioPlayback {
  final ap.AudioPlayer _player;
  RealAudioPlayback([ap.AudioPlayer? player]) : _player = player ?? ap.AudioPlayer();

  @override
  // ignore: avoid_returning_null_for_void
  Stream<void> get onPlayerComplete => _player.onPlayerComplete.map((_) => null);
  @override
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;
  @override
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;

  @override
  @override
  Future<void> play(dynamic source) async {
    // audioplayers expects a Source. Allow callers to pass a file path (String), an
    // existing ap.Source, or any object that can be converted to string (fallback).
    ap.Source src;
    if (source is String) {
      src = ap.DeviceFileSource(source);
    } else if (source is ap.Source) {
      src = source;
    } else {
      // Best-effort fallback: convert to string and treat as file path.
      src = ap.DeviceFileSource(source.toString());
    }

    await _player.play(src);
  }

  @override
  Future<void> stop() async => _player.stop();

  @override
  Future<void> dispose() async => _player.dispose();

  @override
  Future<void> setReleaseMode(dynamic mode) async => _player.setReleaseMode(mode);
}
