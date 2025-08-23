import 'package:ai_chan/chat/infrastructure/repositories/local_chat_repository.dart';
import 'package:ai_chan/chat/infrastructure/adapters/ai_chat_response_adapter.dart';
import 'package:ai_chan/chat/infrastructure/adapters/audio_chat_service.dart';
import 'package:ai_chan/core/interfaces/i_chat_response_service.dart';
import 'package:ai_chan/core/interfaces/i_chat_repository.dart';
import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:ai_chan/core/interfaces/ai_service.dart';
import 'package:ai_chan/core/interfaces/i_profile_service.dart';
import 'package:ai_chan/onboarding/infrastructure/adapters/profile_adapter.dart';
import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'package:ai_chan/core/interfaces/tts_service.dart';
import 'package:ai_chan/voice/infrastructure/adapters/default_tts_service.dart';
import 'package:ai_chan/voice/infrastructure/adapters/google_stt_adapter.dart';
import 'package:ai_chan/voice/infrastructure/adapters/google_tts_adapter.dart';
import 'dart:typed_data';
import 'package:ai_chan/voice/infrastructure/clients/openai_realtime_client.dart';
import 'package:ai_chan/core/interfaces/i_realtime_client.dart';
import 'package:ai_chan/core/infrastructure/adapters/openai_adapter.dart';
import 'package:ai_chan/core/infrastructure/adapters/gemini_adapter.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/runtime_factory.dart' as runtime_factory;
import 'package:ai_chan/voice/infrastructure/audio/audio_playback.dart';

/// Pequeñas fábricas/funciones de DI para la migración incremental.
/// Idealmente esto evolucionará a un contenedor/locator más completo.
IChatRepository getChatRepository() => LocalChatRepository();

IChatResponseService getChatResponseService() => const AiChatResponseAdapter();

/// Factory for audio chat service with required callbacks
IAudioChatService getAudioChatService({
  required void Function() onStateChanged,
  required void Function(List<int>) onWaveform,
}) => AudioChatService(onStateChanged: onStateChanged, onWaveform: onWaveform);

/// Fábrica centralizada para obtener instancias de `IAIService` por modelo.
/// Mantiene singletons por proveedor para reutilizar estado interno (caches, preferencias de clave, etc.).
final Map<String, IAIService> _aiServiceSingletons = {};

IAIService getAIServiceForModel(String modelId) {
  final normalized = modelId.trim().toLowerCase();
  String key = normalized;
  if (key.isEmpty) key = 'default';
  if (_aiServiceSingletons.containsKey(key)) return _aiServiceSingletons[key]!;

  IAIService impl;
  if (normalized.startsWith('gpt-')) {
    final runtime = runtime_factory.getRuntimeAIServiceForModel(normalized);
    impl = OpenAIAdapter(modelId: normalized, runtime: runtime);
  } else if (normalized.startsWith('gemini-') || normalized.startsWith('imagen-')) {
    final runtime = runtime_factory.getRuntimeAIServiceForModel(normalized);
    impl = GeminiAdapter(modelId: normalized, runtime: runtime);
  } else if (normalized.isEmpty) {
    // Default behavior: require configured default model; fail fast if missing
    final defaultModel = Config.requireDefaultTextModel();
    final runtime = runtime_factory.getRuntimeAIServiceForModel(defaultModel);
    if (defaultModel.startsWith('gpt-')) {
      impl = OpenAIAdapter(modelId: defaultModel, runtime: runtime);
    } else {
      impl = GeminiAdapter(modelId: defaultModel, runtime: runtime);
    }
  } else {
    // Fallback: prefer configured DEFAULT_TEXT_MODEL, otherwise fall back to Gemini as project-wide default
    final fallbackModel = Config.requireDefaultTextModel();
    final runtime = runtime_factory.getRuntimeAIServiceForModel(fallbackModel);
    // Choose adapter based on resolved runtime (runtime factory inspects prefix)
    if (fallbackModel.startsWith('gpt-')) {
      impl = OpenAIAdapter(modelId: fallbackModel, runtime: runtime);
    } else {
      impl = GeminiAdapter(modelId: fallbackModel, runtime: runtime);
    }
  }
  _aiServiceSingletons[key] = impl;
  return impl;
}

/// Fábrica para obtener las implementaciones runtime de `AIService` (OpenAIService/GeminiService)
// Use centralized runtime factory from `lib/core/runtime_factory.dart`

ISttService getSttService() => _testSttOverride ?? const GoogleSttAdapter();

ITtsService getTtsService() => const DefaultTtsService();

// Test-time overrides (used by tests to inject fakes without touching DI calls)
ISttService? _testSttOverride;

/// Audio playback test override (allows tests to inject a fake playback globally).
AudioPlayback? _testAudioPlaybackOverride;

/// Factory for production code to obtain an AudioPlayback instance. Tests can
/// override it via [setTestAudioPlaybackOverride].
AudioPlayback getAudioPlayback([dynamic candidate]) {
  if (_testAudioPlaybackOverride != null) return _testAudioPlaybackOverride!;
  return AudioPlayback.adapt(candidate);
}

void setTestAudioPlaybackOverride(AudioPlayback? impl) {
  _testAudioPlaybackOverride = impl;
}

/// Permite a los tests inyectar un ISttService falso globalmente.
void setTestSttOverride(ISttService? impl) {
  _testSttOverride = impl;
}

/// Provider-specific factories (useful for calls where we want Google-backed STT/TTS)
ISttService getSttServiceForProvider(String provider) {
  final p = provider.toLowerCase();
  if (p == 'google') {
    return _testSttOverride ?? const GoogleSttAdapter();
  }
  return getSttService();
}

ITtsService getTtsServiceForProvider(String provider) {
  final p = provider.toLowerCase();
  if (p == 'google') {
    return const GoogleTtsAdapter();
  }
  return getTtsService();
}

/// Fábrica que devuelve un cliente realtime compatible con la interfaz usada por VoiceCallController.
/// Para 'openai' devuelve el OpenAIRealtimeClient; para 'google' devuelve el GeminiCallOrchestrator (emulación).
IRealtimeClient getRealtimeClientForProvider(
  String provider, {
  String? model,
  void Function(String)? onText,
  void Function(Uint8List)? onAudio,
  void Function()? onCompleted,
  void Function(Object)? onError,
  void Function(String)? onUserTranscription,
}) {
  // Test override: if tests provided a factory, use it so tests can inject
  // a fake realtime client wired with the same callbacks the production
  // code would receive. This avoids touching network stacks in tests.
  if (_testRealtimeClientFactory != null) {
    return _testRealtimeClientFactory!(
      provider,
      model: model,
      onText: onText,
      onAudio: onAudio,
      onCompleted: onCompleted,
      onError: onError,
      onUserTranscription: onUserTranscription,
    );
  }
  final p = provider.toLowerCase();
  if (p == 'openai') {
    return OpenAIRealtimeClient(
      model: model ?? Config.requireOpenAIRealtimeModel(),
      onText: onText,
      onAudio: onAudio,
      onCompleted: onCompleted,
      onError: onError,
      onUserTranscription: onUserTranscription,
    );
  }
  // Calls using Gemini/Google are disabled by project decision. Return a
  // lightweight stub so callers can still construct a client but any call
  // orchestration features will surface a clear unsupported error or no-op.
  return OpenAIRealtimeClient(
    model: model ?? 'disabled',
    onText: onText,
    onAudio: onAudio,
    onCompleted: onCompleted,
    onError: onError,
    onUserTranscription: onUserTranscription,
  );
}

// ---------------- Test overrides for realtime client ----------------
/// Type of factory used by tests to create a fake IRealtimeClient that
/// mirrors the production constructor signature.
typedef RealtimeClientFactory =
    IRealtimeClient Function(
      String provider, {
      String? model,
      void Function(String)? onText,
      void Function(Uint8List)? onAudio,
      void Function()? onCompleted,
      void Function(Object)? onError,
      void Function(String)? onUserTranscription,
    });

RealtimeClientFactory? _testRealtimeClientFactory;

/// Allow tests to install a factory to create a fake realtime client.
void setTestRealtimeClientFactory(RealtimeClientFactory? factory) {
  _testRealtimeClientFactory = factory;
}

IProfileService getProfileServiceForProvider([String? provider]) {
  // If caller passes provider explicitly, use it.
  if (provider != null && provider.trim().isNotEmpty) {
    final p = provider.toLowerCase();
    if (p == 'google' || p == 'gemini') {
      final imgModel = Config.getDefaultImageModel().isNotEmpty
          ? Config.getDefaultImageModel()
          : Config.getDefaultImageModel();
      // If still empty, fall back to a reasonable image-capable model
      final resolvedImg = imgModel.isNotEmpty ? imgModel : 'gpt-4.1-mini';
      return ProfileAdapter(aiService: runtime_factory.getRuntimeAIServiceForModel(resolvedImg));
    }
    if (p == 'openai') {
      final txtModel = Config.getDefaultTextModel().isNotEmpty
          ? Config.getDefaultTextModel()
          : Config.getDefaultTextModel();
      final resolvedTxt = txtModel.isNotEmpty ? txtModel : 'gpt-5-mini';
      return ProfileAdapter(aiService: runtime_factory.getRuntimeAIServiceForModel(resolvedTxt));
    }
    final fallbackImg = Config.getDefaultImageModel().isNotEmpty
        ? Config.getDefaultImageModel()
        : Config.getDefaultImageModel();
    final resolvedFallbackImg = fallbackImg.isNotEmpty ? fallbackImg : 'gpt-4.1-mini';
    return ProfileAdapter(aiService: runtime_factory.getRuntimeAIServiceForModel(resolvedFallbackImg));
  }

  // Otherwise, prefer the DEFAULT_TEXT_MODEL from config to infer the provider.
  final defaultTextModel = Config.getDefaultTextModel();
  final defaultImageModel = Config.getDefaultImageModel();
  String resolved = '';
  final modelToCheck = (defaultTextModel.isNotEmpty ? defaultTextModel : defaultImageModel).toLowerCase();
  if (modelToCheck.isNotEmpty) {
    if (modelToCheck.startsWith('gpt-')) resolved = 'openai';
    if (modelToCheck.startsWith('gemini-') || modelToCheck.startsWith('imagen-')) {
      resolved = 'google';
    }
  }

  // If we couldn't infer from DEFAULT_TEXT_MODEL/DEFAULT_IMAGE_MODEL, default to Gemini ('google').
  // This corresponds to using 'gemini-2.5-flash' as the default text model.
  if (resolved.isEmpty) {
    resolved = 'google';
  }

  if (resolved == 'google' || resolved == 'gemini') {
    return ProfileAdapter(aiService: runtime_factory.getRuntimeAIServiceForModel(Config.requireDefaultImageModel()));
  }
  if (resolved == 'openai') {
    return ProfileAdapter(aiService: runtime_factory.getRuntimeAIServiceForModel(Config.requireDefaultTextModel()));
  }
  return ProfileAdapter(aiService: runtime_factory.getRuntimeAIServiceForModel(Config.requireDefaultImageModel()));
}
