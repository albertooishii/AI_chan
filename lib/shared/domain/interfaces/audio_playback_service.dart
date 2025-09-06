import 'dart:async';

/// Domain interface for audio playback service
/// Defines the contract for playing audio across the application
abstract interface class AudioPlaybackService {
  /// Stream that emits when player completes playback
  Stream<void> get onPlayerComplete;

  /// Stream that emits duration changes
  Stream<Duration> get onDurationChanged;

  /// Stream that emits position changes during playback
  Stream<Duration> get onPositionChanged;

  /// Play audio from the given source (file path, URL, or bytes)
  Future<void> play(final dynamic source);

  /// Stop current playback
  Future<void> stop();

  /// Dispose of the player and release resources
  Future<void> dispose();

  /// Set release mode for playback behavior
  Future<void> setReleaseMode(final dynamic mode);
}
