/// 🎯 **Call Audio Controller Interface** - Domain Contract
///
/// Define the contract for call audio operations without
/// depending on specific UI framework implementation.
abstract class ICallAudioController {
  // State getters
  bool get isMuted;
  double get volume;
  bool get isRecording;

  // Audio operations
  Future<void> toggleMute();
  Future<void> setVolume(final double volume);
  Future<void> startRecording();
  Future<void> stopRecording();
  void dispose();
}

/// 🎯 **Call State Controller Interface** - Domain Contract
abstract class ICallStateController {
  // State getters
  dynamic get currentState; // Call state enum
  bool get isConnected;
  String get connectionQuality;

  // State operations
  void updateState(final dynamic newState);
  void updateConnectionQuality(final String quality);
  void dispose();
}

/// 🎯 **Call UI Controller Interface** - Domain Contract
abstract class ICallUIController {
  // UI state getters
  bool get isVisible;
  bool get isFullscreen;

  // UI operations
  void show();
  void hide();
  void toggleFullscreen();
  void dispose();
}

/// 🎯 **Call Playback Controller Interface** - Domain Contract
abstract class ICallPlaybackController {
  // Playback state getters
  bool get isPlaying;
  Duration get currentPosition;
  Duration get totalDuration;

  // Playback operations
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seekTo(final Duration position);
  void dispose();
}

/// 🎯 **Call Recording Controller Interface** - Domain Contract
abstract class ICallRecordingController {
  // Recording state getters
  bool get isRecording;
  Duration get recordingDuration;

  // Recording operations
  Future<void> startRecording();
  Future<void> stopRecording();
  Future<void> pauseRecording();
  Future<void> resumeRecording();
  void dispose();
}
