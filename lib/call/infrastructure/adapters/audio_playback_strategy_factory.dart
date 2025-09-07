import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/call/domain/interfaces/i_audio_playback_strategy.dart';
import 'audio_playback_strategy.dart';

/// Factory for creating audio playback strategies
class AudioPlaybackStrategyFactory implements IAudioPlaybackStrategyFactory {
  final Map<String, IAudioPlaybackStrategy> _strategies = {};

  @override
  IAudioPlaybackStrategy createStrategy(final String aiProvider) {
    // Convertir provider string a enum si es necesario
    final RealtimeProvider? provider = _parseProvider(aiProvider);
    if (provider == null) {
      return getDefaultStrategy();
    }

    return _createStrategyForProvider(provider);
  }

  @override
  IAudioPlaybackStrategy getDefaultStrategy() {
    return OpenAIAudioPlaybackStrategy();
  }

  @override
  void registerStrategy(
    final String provider,
    final IAudioPlaybackStrategy strategy,
  ) {
    _strategies[provider] = strategy;
  }

  /// Creates appropriate strategy based on realtime provider
  static AudioPlaybackStrategy createStrategyStatic({
    required final RealtimeProvider provider,
  }) {
    final factory = AudioPlaybackStrategyFactory();
    return factory._createStrategyForProvider(provider)
        as AudioPlaybackStrategy;
  }

  IAudioPlaybackStrategy _createStrategyForProvider(
    final RealtimeProvider provider,
  ) {
    switch (provider) {
      case RealtimeProvider.openai:
        return OpenAIAudioPlaybackStrategy();

      case RealtimeProvider.gemini:
        return GeminiAudioPlaybackStrategy();
    }
  }

  RealtimeProvider? _parseProvider(final String aiProvider) {
    switch (aiProvider.toLowerCase()) {
      case 'openai':
        return RealtimeProvider.openai;
      case 'gemini':
        return RealtimeProvider.gemini;
      default:
        return null;
    }
  }
}
