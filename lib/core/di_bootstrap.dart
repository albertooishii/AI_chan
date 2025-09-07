import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/call/infrastructure/services/openai_realtime_client.dart';
import 'package:ai_chan/call/infrastructure/services/gemini_realtime_client.dart';
import 'package:ai_chan/core/config.dart';

/// Centraliza las registraciones de factories para reproducir el bootstrap
/// que antes vivía en `main.dart`. Mantiene `main.dart` más pequeño y
/// facilita testing / reuso.
void registerDefaultRealtimeClientFactories() {
  // OpenAI factory
  di.registerRealtimeClientFactory('openai', ({
    final model,
    final onText,
    final onAudio,
    final onCompleted,
    final onError,
    final onUserTranscription,
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

  // Factory compartido para Gemini/Google
  GeminiRealtimeClient geminiFactory({
    final model,
    final onText,
    final onAudio,
    final onCompleted,
    final onError,
    final onUserTranscription,
  }) {
    return GeminiRealtimeClient();
  }

  // Gemini factory: uses a minimal GeminiRealtimeClient skeleton for now.
  di.registerRealtimeClientFactory('gemini', geminiFactory);

  // Alias 'google' to the same Gemini factory for backwards compatibility.
  di.registerRealtimeClientFactory('google', geminiFactory);
}
