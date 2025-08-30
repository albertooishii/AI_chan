import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/voice/infrastructure/clients/openai_realtime_client.dart';
import 'package:ai_chan/voice/infrastructure/clients/gemini_realtime_client.dart';
import 'package:ai_chan/core/config.dart';

/// Centraliza las registraciones de factories para reproducir el bootstrap
/// que antes vivía en `main.dart`. Mantiene `main.dart` más pequeño y
/// facilita testing / reuso.
void registerDefaultRealtimeClientFactories() {
  // OpenAI factory
  di.registerRealtimeClientFactory('openai', ({
    model,
    onText,
    onAudio,
    onCompleted,
    onError,
    onUserTranscription,
  }) {
    return OpenAIRealtimeClient(
      model: model ?? Config.requireOpenAIRealtimeModel(),
      onText: onText,
      onAudio: onAudio,
      onCompleted: onCompleted,
      onError: onError,
      onUserTranscription: onUserTranscription,
    );
  });

  // Gemini / Google factory: uses a minimal GeminiRealtimeClient skeleton for now.
  di.registerRealtimeClientFactory('gemini', ({
    model,
    onText,
    onAudio,
    onCompleted,
    onError,
    onUserTranscription,
  }) {
    return GeminiRealtimeClient();
  });

  // Alias 'google' to the same Gemini factory for backwards compatibility.
  di.registerRealtimeClientFactory('google', ({
    model,
    onText,
    onAudio,
    onCompleted,
    onError,
    onUserTranscription,
  }) {
    return GeminiRealtimeClient();
  });
}
