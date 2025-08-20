import 'dart:async';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Abstract strategy for audio playback scheduling
abstract class AudioPlaybackStrategy {
  /// Schedule audio playback with provider-specific timing
  void schedulePlayback(Function playbackFunction);
}

/// OpenAI audio playback strategy with 40ms delay
class OpenAIAudioPlaybackStrategy implements AudioPlaybackStrategy {
  @override
  void schedulePlayback(Function playbackFunction) {
    Log.d('OpenAI strategy: Scheduling playback with 40ms delay');
    Timer(const Duration(milliseconds: 40), () {
      try {
        playbackFunction();
      } catch (e) {
        Log.e('Error in OpenAI playback: $e');
      }
    });
  }
}

/// Gemini audio playback strategy with 200ms delay and retry logic
class GeminiAudioPlaybackStrategy implements AudioPlaybackStrategy {
  @override
  void schedulePlayback(Function playbackFunction) {
    Log.d('Gemini strategy: Scheduling playback with 200ms delay + retry');
    Timer(const Duration(milliseconds: 200), () {
      try {
        playbackFunction();
      } catch (e) {
        Log.e('Error in Gemini playback, retrying in 100ms: $e');
        // Retry logic for Gemini
        Timer(const Duration(milliseconds: 100), () {
          try {
            playbackFunction();
          } catch (retryError) {
            Log.e('Gemini retry failed: $retryError');
          }
        });
      }
    });
  }
}
