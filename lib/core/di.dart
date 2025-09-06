import 'package:ai_chan/chat/infrastructure/repositories/local_chat_repository.dart';
import 'package:ai_chan/chat/infrastructure/adapters/audio_chat_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';
import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_language_resolver.dart';
import 'package:ai_chan/chat/infrastructure/adapters/language_resolver_service.dart';
import 'package:ai_chan/core/interfaces/ai_service.dart';
import 'package:ai_chan/core/interfaces/i_profile_service.dart';
import 'package:ai_chan/onboarding/infrastructure/adapters/profile_adapter.dart';
import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'package:ai_chan/core/interfaces/tts_service.dart';
import 'package:ai_chan/call/infrastructure/adapters/default_tts_service.dart';
import 'package:ai_chan/call/infrastructure/adapters/google_stt_adapter.dart';
import 'package:ai_chan/call/infrastructure/adapters/openai_stt_adapter.dart';
import 'package:ai_chan/call/infrastructure/adapters/android_native_stt_adapter.dart';
import 'package:ai_chan/call/infrastructure/adapters/google_tts_adapter.dart';
import 'dart:typed_data';
import 'package:ai_chan/core/interfaces/i_realtime_client.dart';
import 'package:ai_chan/core/infrastructure/adapters/openai_adapter.dart';
import 'package:ai_chan/core/infrastructure/adapters/gemini_adapter.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/services/ai_runtime_provider.dart'
    as runtime_factory;
import 'package:ai_chan/shared/infrastructure/audio/audio_playback.dart';
import 'package:ai_chan/call/application/interfaces/voice_call_controller_builder.dart';
import 'package:ai_chan/call/infrastructure/builders/voice_call_controller_builder.dart';
import 'package:ai_chan/shared/domain/interfaces/i_file_service.dart';
import 'package:ai_chan/shared/infrastructure/services/file_service.dart';
import 'package:ai_chan/shared/domain/interfaces/i_file_operations_service.dart';
import 'package:ai_chan/shared/infrastructure/services/file_operations_service.dart';
import 'package:ai_chan/shared/application/services/file_ui_service.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';
import 'package:ai_chan/chat/application/controllers/chat_controller.dart';
import 'package:ai_chan/chat/infrastructure/services/prompt_builder_service.dart';

/// Pequeñas fábricas/funciones de DI para la migración incremental.
/// Idealmente esto evolucionará a un contenedor/locator más completo.
IChatRepository getChatRepository() => LocalChatRepository();

/// Factory for file operations service - DDD compliance
IFileOperationsService getFileOperationsService() => FileOperationsService();

/// Factory for File UI Service - DDD compliance for presentation layer
FileUIService getFileUIService() => FileUIService(getFileOperationsService());

// DI factories and small helpers used across the app. Legacy adapters have
// been removed and their logic migrated into higher-level use-cases such
// as `SendMessageUseCase` and `AIService` — keep this file focused on
// active factory functions and test overrides.

/// Factory for audio chat service with required callbacks
IAudioChatService getAudioChatService({
  required final void Function() onStateChanged,
  required final void Function(List<int>) onWaveform,
}) => AudioChatService(onStateChanged: onStateChanged, onWaveform: onWaveform);

/// Fábrica centralizada para obtener instancias de `IAIService` por modelo.
/// Mantiene singletons por proveedor para reutilizar estado interno (caches, preferencias de clave, etc.).
final Map<String, IAIService> _aiServiceSingletons = {};

IAIService getAIServiceForModel(final String modelId) {
  final normalized = modelId.trim().toLowerCase();
  String key = normalized;
  if (key.isEmpty) key = 'default';
  if (_aiServiceSingletons.containsKey(key)) return _aiServiceSingletons[key]!;

  IAIService impl;
  if (normalized.startsWith('gpt-')) {
    final runtime = runtime_factory.getRuntimeAIServiceForModel(normalized);
    impl = OpenAIAdapter(modelId: normalized, runtime: runtime);
  } else if (normalized.startsWith('gemini-') ||
      normalized.startsWith('imagen-')) {
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

/// Factory for language resolver - resolves language codes from TTS voice names
ILanguageResolver getLanguageResolver() => LanguageResolverService();

/// Factory for file service - handles file operations
IFileService getFileService() => FileService();

/// Factory for voice call controller builder
IVoiceCallControllerBuilder getVoiceCallControllerBuilder() =>
    VoiceCallControllerBuilder();

// Test-time overrides (used by tests to inject fakes without touching DI calls)
ISttService? _testSttOverride;

/// Audio playback test override (allows tests to inject a fake playback globally).
AudioPlayback? _testAudioPlaybackOverride;

/// Factory for production code to obtain an AudioPlayback instance. Tests can
/// override it via [setTestAudioPlaybackOverride].
AudioPlayback getAudioPlayback([final dynamic candidate]) {
  if (_testAudioPlaybackOverride != null) return _testAudioPlaybackOverride!;
  return AudioPlayback.adapt(candidate);
}

void setTestAudioPlaybackOverride(final AudioPlayback? impl) {
  _testAudioPlaybackOverride = impl;
}

/// Permite a los tests inyectar un ISttService falso globalmente.
void setTestSttOverride(final ISttService? impl) {
  _testSttOverride = impl;
}

/// Provider-specific factories (useful for calls where we want Google-backed STT/TTS)
ISttService getSttServiceForProvider(final String provider) {
  final p = provider.toLowerCase();
  if (p == 'google') {
    return _testSttOverride ?? const GoogleSttAdapter();
  }
  if (p == 'openai') {
    return _testSttOverride ?? const OpenAISttAdapter();
  }
  if (p == 'native' || p == 'android_native') {
    return _testSttOverride ?? const AndroidNativeSttAdapter();
  }
  return getSttService();
}

ITtsService getTtsServiceForProvider(final String provider) {
  final p = provider.toLowerCase();
  if (p == 'google') {
    return const GoogleTtsAdapter();
  }
  return getTtsService();
}

/// Fábrica que devuelve un cliente realtime compatible con la interfaz usada por VoiceCallController.
/// Para 'openai' devuelve el OpenAIRealtimeClient; para 'google' devuelve el GeminiCallOrchestrator (emulación).
// ---------------- Realtime client registry ----------------
/// Factory signature for provider-specific realtime client creators.
typedef RealtimeClientCreator =
    IRealtimeClient Function({
      String? model,
      void Function(String)? onText,
      void Function(Uint8List)? onAudio,
      void Function()? onCompleted,
      void Function(Object)? onError,
      void Function(String)? onUserTranscription,
    });

final Map<String, RealtimeClientCreator> _realtimeClientRegistry = {};

/// Register a realtime client factory for a provider key (e.g. 'openai', 'google').
void registerRealtimeClientFactory(
  final String provider,
  final RealtimeClientCreator creator,
) {
  _realtimeClientRegistry[provider.trim().toLowerCase()] = creator;
}

// Note: creators for specific providers should be registered at bootstrap
// using `registerRealtimeClientFactory(provider, creator)` so the app can
// choose which providers to enable at runtime.

/// A fallback client returned when a provider has not been registered.
class NotSupportedRealtimeClient implements IRealtimeClient {
  NotSupportedRealtimeClient(this.provider);
  final String provider;

  @override
  bool get isConnected => false;

  @override
  void appendAudio(final List<int> bytes) {
    // no-op
  }

  @override
  Future<void> close() async {
    // no-op
  }

  @override
  Future<void> commitPendingAudio() async {
    // no-op
  }

  @override
  Future<void> connect({
    required final String systemPrompt,
    final String voice = 'marin',
    final String? inputAudioFormat,
    final String? outputAudioFormat,
    final String? turnDetectionType,
    final int? silenceDurationMs,
    final Map<String, dynamic>? options,
  }) async {
    throw UnsupportedError(
      'Realtime provider "$provider" not supported/configured',
    );
  }

  @override
  void requestResponse({final bool audio = true, final bool text = true}) {
    // no-op
  }

  @override
  void sendText(final String text) {
    // no-op
  }

  @override
  void updateVoice(final String voice) {
    // no-op
  }

  // Implementaciones por defecto de los nuevos métodos
  @override
  void sendImageWithText({
    required final String imageBase64,
    final String? text,
    final String imageFormat = 'png',
  }) {
    // no-op - funcionalidad no soportada
  }

  @override
  void configureTools(final List<Map<String, dynamic>> tools) {
    // no-op - funcionalidad no soportada
  }

  @override
  void sendFunctionCallOutput({
    required final String callId,
    required final String output,
  }) {
    // no-op - funcionalidad no soportada
  }

  @override
  void cancelResponse({final String? itemId, final int? sampleCount}) {
    // no-op - funcionalidad no soportada
  }
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
void setTestRealtimeClientFactory(final RealtimeClientFactory? factory) {
  _testRealtimeClientFactory = factory;
}

/// Factory that uses the registry (or the test override) to create a realtime client.
IRealtimeClient getRealtimeClientForProvider(
  final String provider, {
  final String? model,
  final void Function(String)? onText,
  final void Function(Uint8List)? onAudio,
  final void Function()? onCompleted,
  final void Function(Object)? onError,
  final void Function(String)? onUserTranscription,
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

  final p = provider.trim().toLowerCase();
  final creator = _realtimeClientRegistry[p];
  if (creator != null) {
    return creator(
      model: model,
      onText: onText,
      onAudio: onAudio,
      onCompleted: onCompleted,
      onError: onError,
      onUserTranscription: onUserTranscription,
    );
  }

  // If the provider isn't registered we return a clear fallback that will
  // throw on connect. This forces callers to register new providers (eg. Gemini)
  // via `registerRealtimeClientFactory` rather than sprinkling provider checks.
  return NotSupportedRealtimeClient(provider);
}

IProfileService getProfileServiceForProvider([final String? provider]) {
  // If caller passes provider explicitly, use it.
  if (provider != null && provider.trim().isNotEmpty) {
    final p = provider.toLowerCase();
    if (p == 'google' || p == 'gemini') {
      final imgModel = Config.getDefaultImageModel().isNotEmpty
          ? Config.getDefaultImageModel()
          : Config.getDefaultImageModel();
      // If still empty, fall back to a reasonable image-capable model
      final resolvedImg = imgModel.isNotEmpty ? imgModel : 'gpt-4.1-mini';
      return ProfileAdapter(
        aiService: runtime_factory.getRuntimeAIServiceForModel(resolvedImg),
      );
    }
    if (p == 'openai') {
      final txtModel = Config.getDefaultTextModel().isNotEmpty
          ? Config.getDefaultTextModel()
          : Config.getDefaultTextModel();
      final resolvedTxt = txtModel.isNotEmpty ? txtModel : 'gpt-4.1-mini';
      return ProfileAdapter(
        aiService: runtime_factory.getRuntimeAIServiceForModel(resolvedTxt),
      );
    }
    final fallbackImg = Config.getDefaultImageModel().isNotEmpty
        ? Config.getDefaultImageModel()
        : Config.getDefaultImageModel();
    final resolvedFallbackImg = fallbackImg.isNotEmpty
        ? fallbackImg
        : 'gpt-4.1-mini';
    return ProfileAdapter(
      aiService: runtime_factory.getRuntimeAIServiceForModel(
        resolvedFallbackImg,
      ),
    );
  }

  // Otherwise, prefer the DEFAULT_TEXT_MODEL from config to infer the provider.
  final defaultTextModel = Config.getDefaultTextModel();
  final defaultImageModel = Config.getDefaultImageModel();
  String resolved = '';
  final modelToCheck =
      (defaultTextModel.isNotEmpty ? defaultTextModel : defaultImageModel)
          .toLowerCase();
  if (modelToCheck.isNotEmpty) {
    if (modelToCheck.startsWith('gpt-')) resolved = 'openai';
    if (modelToCheck.startsWith('gemini-') ||
        modelToCheck.startsWith('imagen-')) {
      resolved = 'google';
    }
  }

  // If we couldn't infer from DEFAULT_TEXT_MODEL/DEFAULT_IMAGE_MODEL, default to Gemini ('google').
  // This corresponds to using 'gemini-2.5-flash' as the default text model.
  if (resolved.isEmpty) {
    resolved = 'google';
  }

  if (resolved == 'google' || resolved == 'gemini') {
    return ProfileAdapter(
      aiService: runtime_factory.getRuntimeAIServiceForModel(
        Config.requireDefaultImageModel(),
      ),
    );
  }
  if (resolved == 'openai') {
    return ProfileAdapter(
      aiService: runtime_factory.getRuntimeAIServiceForModel(
        Config.requireDefaultTextModel(),
      ),
    );
  }
  return ProfileAdapter(
    aiService: runtime_factory.getRuntimeAIServiceForModel(
      Config.requireDefaultImageModel(),
    ),
  );
}

/// Factory for Chat Application Service - nueva arquitectura DDD
ChatApplicationService getChatApplicationService() => ChatApplicationService(
  repository: getChatRepository(),
  promptBuilder: PromptBuilderService(),
  fileOperations: getFileOperationsService(),
);

/// Factory for Chat Controller - nueva arquitectura DDD
ChatController getChatController() =>
    ChatController(chatService: getChatApplicationService());
