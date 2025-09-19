import 'package:ai_chan/shared/domain/models/index.dart';

typedef OnStateChanged = void Function();
typedef OnWaveformUpdate = void Function(List<int> waveform);

/// Interface for audio chat services that handle recording, transcription, and playback
abstract class IAudioChatService {
  /// Current recording state
  bool get isRecording;

  /// Current waveform data
  List<int> get currentWaveform;

  /// Live transcript from ongoing recording
  String get liveTranscript;

  /// Duration of current recording
  Duration get recordingElapsed;

  /// Current playback position
  Duration get currentPosition;

  /// Current playback duration
  Duration get currentDuration;

  /// Check if a message is currently playing
  bool isPlayingMessage(final Message message);

  /// Start audio recording
  Future<void> startRecording();

  /// Stop recording and return the file path
  Future<String?> stopRecording({final bool cancelled = false});

  /// Cancel current recording
  Future<void> cancelRecording();

  /// Toggle playback of a message
  Future<void> togglePlay(final Message message, final OnStateChanged onState);

  /// Synthesize text to speech and return audio file path
  Future<String?> synthesizeTts(
    final String text, {
    final String? languageCode,
    final bool forDialogDemo = false,
  });

  /// Dispose of resources
  void dispose();
}
