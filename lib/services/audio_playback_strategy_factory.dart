import '../models/realtime_provider.dart';
import 'audio_playback_strategy.dart';

/// Factory for creating audio playback strategies
class AudioPlaybackStrategyFactory {
  /// Creates appropriate strategy based on realtime provider
  static AudioPlaybackStrategy createStrategy({required RealtimeProvider provider}) {
    switch (provider) {
      case RealtimeProvider.openai:
        return OpenAIAudioPlaybackStrategy();

      case RealtimeProvider.gemini:
        return GeminiAudioPlaybackStrategy();
    }
  }
}
