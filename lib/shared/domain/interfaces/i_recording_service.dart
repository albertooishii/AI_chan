import 'dart:async';
import 'dart:typed_data';

/// 🎯 **Recording Service Interface** - Domain Abstraction for Audio Recording
///
/// Defines the contract for audio recording operations without external dependencies.
/// This allows the application layer to use recording functionality through domain interfaces.
///
/// **Clean Architecture Compliance:**
/// ✅ Application layer depends only on domain interfaces
/// ✅ No direct external package dependencies
/// ✅ Platform-agnostic recording operations
abstract class IRecordingService {
  /// Whether recording is currently active
  bool get isRecording;

  /// Whether the recording service is initialized
  bool get isInitialized;

  /// Current recording duration
  Duration get currentDuration;

  /// Initialize the recording service
  Future<void> initialize();

  /// Start recording to a file
  Future<String> startRecording(final String filePath);

  /// Stop current recording
  Future<String?> stopRecording();

  /// Pause current recording
  Future<void> pauseRecording();

  /// Resume paused recording
  Future<void> resumeRecording();

  /// Cancel current recording
  Future<void> cancelRecording();

  /// Get current recording amplitude (for waveform visualization)
  Future<double> getAmplitude();

  /// Check if microphone permission is granted
  Future<bool> hasPermission();

  /// Request microphone permission
  Future<bool> requestPermission();

  /// Dispose of recording resources
  Future<void> dispose();

  /// Stream of recording state changes
  Stream<RecordingState> get recordingStateStream;

  /// Stream of amplitude data for waveform
  Stream<double> get amplitudeStream;

  /// Start recording stream (for real-time audio processing)
  Future<Stream<Uint8List>> startStream(final RecordingConfig config);

  /// Stop recording stream
  Future<void> stopStream();

  /// Check if stream is active
  bool get isStreamActive;
}

/// 🎯 **Recording State** - Represents the current state of recording
enum RecordingState {
  /// Recording is not active
  idle,

  /// Recording is being initialized
  initializing,

  /// Recording is active
  recording,

  /// Recording is paused
  paused,

  /// Recording is stopping
  stopping,

  /// An error occurred during recording
  error,
}

/// 🎯 **Recording Configuration** - Configuration for recording sessions
class RecordingConfig {
  const RecordingConfig({
    this.sampleRate = 44100,
    this.bitRate = 128000,
    this.channels = 1,
    this.encoder = AudioEncoder.aac,
  });

  final int sampleRate;
  final int bitRate;
  final int channels;
  final AudioEncoder encoder;
}

/// 🎯 **Audio Encoder Types** - Supported audio encoding formats
enum AudioEncoder {
  /// AAC encoding
  aac,

  /// WAV encoding (uncompressed)
  wav,

  /// MP3 encoding
  mp3,

  /// Opus encoding
  opus,
}

/// 🎯 **Recording Result** - Result of a recording operation
class RecordingResult {
  factory RecordingResult.success({
    required final String filePath,
    final Duration? duration,
    final int? size,
  }) => RecordingResult(
    success: true,
    filePath: filePath,
    duration: duration,
    size: size,
  );

  factory RecordingResult.failure({
    required final String filePath,
    required final String error,
  }) => RecordingResult(success: false, filePath: filePath, error: error);
  const RecordingResult({
    required this.success,
    required this.filePath,
    this.duration,
    this.size,
    this.error,
  });

  final bool success;
  final String filePath;
  final Duration? duration;
  final int? size;
  final String? error;
}
