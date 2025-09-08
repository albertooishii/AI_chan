// lib/core/di.dart
// Dependency Injection Container with Barrel Exports
// This file provides clean imports using barrels instead of individual imports

// ===== BARREL EXPORTS =====
// Core barrels
export 'package:ai_chan/core/interfaces/index.dart';
export 'package:ai_chan/core/infrastructure/adapters/index.dart';
export 'package:ai_chan/core/domain/interfaces/index.dart';
export 'package:ai_chan/core/cache/index.dart';

// Chat bounded context barrels
export 'package:ai_chan/chat/domain/interfaces/index.dart';
export 'package:ai_chan/chat/infrastructure/adapters/index.dart';
export 'package:ai_chan/chat/application/services/index.dart';
export 'package:ai_chan/chat/presentation/controllers/index.dart';
export 'package:ai_chan/chat/application/use_cases/index.dart';
export 'package:ai_chan/chat/infrastructure/services/index.dart';

// Call bounded context barrels
export 'package:ai_chan/call/domain/interfaces/index.dart';
export 'package:ai_chan/call/infrastructure/adapters/index.dart';
export 'package:ai_chan/call/application/use_cases/index.dart';
export 'package:ai_chan/call/application/services/index.dart';
export 'package:ai_chan/call/presentation/controllers/index.dart';
export 'package:ai_chan/call/infrastructure/managers/index.dart';
export 'package:ai_chan/call/infrastructure/services/index.dart';
export 'package:ai_chan/call/domain/services/index.dart';

// Onboarding bounded context barrels
export 'package:ai_chan/onboarding/domain/interfaces/index.dart';
export 'package:ai_chan/onboarding/infrastructure/adapters/index.dart';

// Shared bounded context barrels
export 'package:ai_chan/shared/domain/interfaces/index.dart';
export 'package:ai_chan/shared/infrastructure/services/index.dart';
export 'package:ai_chan/shared/infrastructure/adapters/index.dart';

// ===== INDIVIDUAL IMPORTS =====
// These are kept for services that don't have barrel files yet or need specific imports
import 'dart:typed_data';

import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';
import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_language_resolver.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_promise_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_audio_utils_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_logging_utils_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_preferences_utils_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_debounced_persistence_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_message_queue_manager.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_file_operations_service.dart';
import 'package:ai_chan/chat/infrastructure/adapters/local_chat_repository.dart';
import 'package:ai_chan/chat/infrastructure/adapters/audio_chat_service.dart';
import 'package:ai_chan/chat/infrastructure/adapters/language_resolver_service.dart';
import 'package:ai_chan/core/interfaces/ai_service.dart';
import 'package:ai_chan/onboarding/domain/interfaces/i_profile_service.dart';
import 'package:ai_chan/onboarding/infrastructure/adapters/profile_adapter.dart';
import 'package:ai_chan/call/domain/interfaces/i_speech_service.dart';
import 'package:ai_chan/call/infrastructure/adapters/default_tts_service.dart';
import 'package:ai_chan/call/infrastructure/adapters/openai_stt_adapter.dart';
import 'package:ai_chan/call/infrastructure/adapters/openai_tts_adapter.dart';
import 'package:ai_chan/call/infrastructure/adapters/android_native_stt_adapter.dart';
import 'package:ai_chan/call/infrastructure/adapters/android_native_tts_adapter.dart';
import 'package:ai_chan/core/interfaces/i_realtime_client.dart';
import 'package:ai_chan/core/infrastructure/adapters/openai_adapter.dart';
import 'package:ai_chan/core/infrastructure/adapters/gemini_adapter.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/services/ai_runtime_provider.dart'
    as runtime_factory;
import 'package:ai_chan/shared/services/openai_tts_service.dart';
import 'package:ai_chan/shared/infrastructure/adapters/audio_playback.dart';
import 'package:ai_chan/shared/domain/interfaces/i_file_service.dart';
import 'package:ai_chan/shared/infrastructure/services/file_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_secure_storage_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_backup_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_preferences_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_logging_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_network_service.dart';
import 'package:ai_chan/shared/application/services/file_ui_service.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';
import 'package:ai_chan/chat/presentation/controllers/chat_controller.dart';
import 'package:ai_chan/chat/infrastructure/adapters/prompt_builder_service.dart';
import 'package:ai_chan/call/application/services/voice_call_application_service.dart';
import 'package:ai_chan/call/application/use_cases/start_call_use_case.dart';
import 'package:ai_chan/call/application/use_cases/end_call_use_case.dart';
import 'package:ai_chan/call/application/use_cases/handle_incoming_call_use_case.dart';
import 'package:ai_chan/call/application/use_cases/manage_audio_use_case.dart';
import 'package:ai_chan/call/infrastructure/managers/call_manager_impl.dart';
import 'package:ai_chan/call/infrastructure/managers/audio_manager_impl.dart';
import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';
import 'package:ai_chan/call/domain/interfaces/realtime_transport_service.dart';
import 'package:ai_chan/call/infrastructure/adapters/in_memory_call_repository.dart';
import 'package:ai_chan/call/infrastructure/adapters/flutter_audio_manager.dart';
import 'package:ai_chan/call/infrastructure/adapters/default_call_manager.dart';
import 'package:ai_chan/call/infrastructure/adapters/websocket_realtime_transport_service.dart';
import 'package:ai_chan/call/infrastructure/adapters/openai_realtime_call_client.dart';
import 'package:ai_chan/onboarding/domain/interfaces/i_profile_repository.dart';
import 'package:ai_chan/onboarding/infrastructure/adapters/in_memory_profile_repository.dart';
import 'package:ai_chan/shared/domain/interfaces/audio_playback_service.dart';
import 'package:ai_chan/call/domain/interfaces/i_vad_service.dart';
import 'package:ai_chan/call/infrastructure/vad_service.dart';
import 'package:ai_chan/shared/infrastructure/services/basic_chat_promise_service.dart';
import 'package:ai_chan/shared/infrastructure/services/basic_chat_audio_utils_service.dart';
import 'package:ai_chan/shared/infrastructure/services/basic_chat_logging_utils_service.dart';
import 'package:ai_chan/shared/infrastructure/services/basic_chat_preferences_utils_service.dart';
import 'package:ai_chan/shared/infrastructure/services/basic_chat_debounced_persistence_service.dart';
import 'package:ai_chan/shared/infrastructure/services/basic_chat_message_queue_manager.dart';
import 'package:ai_chan/chat/infrastructure/services/basic_chat_file_operations_service.dart';
import 'package:ai_chan/call/domain/services/call_summary_service.dart';
import 'package:ai_chan/shared/domain/interfaces/i_ui_state_service.dart';
import 'package:ai_chan/shared/infrastructure/services/flutter_secure_storage_service.dart';
import 'package:ai_chan/shared/infrastructure/services/basic_ui_state_service.dart';

// Additional imports for missing services
import 'package:ai_chan/core/domain/interfaces/i_call_to_chat_communication_service.dart';
import 'package:ai_chan/chat/application/adapters/call_to_chat_communication_adapter.dart';
import 'package:ai_chan/call/infrastructure/adapters/google_stt_adapter.dart';
import 'package:ai_chan/call/infrastructure/adapters/google_tts_adapter.dart';
import 'package:ai_chan/shared/infrastructure/services/basic_file_operations_service.dart';
import 'package:ai_chan/shared/domain/interfaces/i_file_operations_service.dart';
import 'package:ai_chan/shared/infrastructure/services/real_preferences_service.dart';

/// Factory functions and small helpers used across the app.
/// This file provides DI factories for the entire application.

IChatRepository getChatRepository() => LocalChatRepository();

/// Factory for file operations service - DDD compliance
IChatFileOperationsService getFileOperationsService() =>
    const BasicChatFileOperationsService();

/// Factory for basic file operations service - DDD compliance
IFileOperationsService getBasicFileOperationsService() =>
    const BasicFileOperationsService();

/// Factory for File UI Service - DDD compliance for presentation layer
FileUIService getFileUIService() =>
    const FileUIService(BasicFileOperationsService());

/// Factory for audio chat service with required callbacks
IAudioChatService getAudioChatService({
  required final void Function() onStateChanged,
  required final void Function(List<int>) onWaveform,
}) => AudioChatService(onStateChanged: onStateChanged, onWaveform: onWaveform);

/// Factory for language resolver - resolves language codes from TTS voice names
ILanguageResolver getLanguageResolver() => LanguageResolverService();

/// Factory for file service - handles file operations
IFileService getFileService() => FileService();

// Test-time overrides
ICallSttService? _testSttOverride;
AudioPlayback? _testAudioPlaybackOverride;

ICallSttService getSttService() => _testSttOverride ?? const GoogleSttAdapter();
ICallTtsService getTtsService() => const DefaultTtsService();

/// Factory for production code to obtain an AudioPlayback instance
AudioPlayback getAudioPlayback([final dynamic candidate]) {
  if (_testAudioPlaybackOverride != null) return _testAudioPlaybackOverride!;
  return AudioPlayback.adapt(candidate);
}

void setTestAudioPlaybackOverride(final AudioPlayback? impl) {
  _testAudioPlaybackOverride = impl;
}

void setTestSttOverride(final ICallSttService? impl) {
  _testSttOverride = impl;
}

/// Provider-specific factories
ICallSttService getSttServiceForProvider(final String provider) {
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

ICallTtsService getTtsServiceForProvider(final String provider) {
  final p = provider.toLowerCase();
  if (p == 'google') {
    return const GoogleTtsAdapter();
  }
  if (p == 'openai') {
    return OpenAITtsAdapter(OpenAITtsService());
  }
  if (p == 'android_native' || p == 'native') {
    return const AndroidNativeTtsAdapter();
  }
  return getTtsService();
}

/// Realtime client registry
typedef RealtimeClientCreator =
    IRealtimeClient Function({
      String? model,
      void Function(String)? onText,
      void Function(Uint8List)? onAudio,
      void Function()? onCompleted,
      void Function(Object)? onError,
      void Function(String)? onUserTranscription,
    });

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

final Map<String, RealtimeClientCreator> _realtimeClientRegistry = {};

void registerRealtimeClientFactory(
  final String provider,
  final RealtimeClientCreator creator,
) {
  _realtimeClientRegistry[provider.trim().toLowerCase()] = creator;
}

RealtimeClientFactory? _testRealtimeClientFactory;

void setTestRealtimeClientFactory(final RealtimeClientFactory? factory) {
  _testRealtimeClientFactory = factory;
}

IRealtimeClient getRealtimeClientForProvider(
  final String provider, {
  final String? model,
  final void Function(String)? onText,
  final void Function(Uint8List)? onAudio,
  final void Function()? onCompleted,
  final void Function(Object)? onError,
  final void Function(String)? onUserTranscription,
}) {
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

  return NotSupportedRealtimeClient(provider);
}

class NotSupportedRealtimeClient implements IRealtimeClient {
  NotSupportedRealtimeClient(this.provider);
  final String provider;

  @override
  bool get isConnected => false;

  @override
  void appendAudio(final List<int> bytes) {}

  @override
  Future<void> close() async {}

  @override
  Future<void> commitPendingAudio() async {}

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
  void requestResponse({final bool audio = true, final bool text = true}) {}

  @override
  void sendText(final String text) {}

  @override
  void updateVoice(final String voice) {}

  @override
  void sendImageWithText({
    required final String imageBase64,
    final String? text,
    final String imageFormat = 'png',
  }) {}

  @override
  void configureTools(final List<Map<String, dynamic>> tools) {}

  @override
  void sendFunctionCallOutput({
    required final String callId,
    required final String output,
  }) {}

  @override
  void cancelResponse({final String? itemId, final int? sampleCount}) {}
}

/// AI Service factory with singleton pattern
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
    final defaultModel = Config.requireDefaultTextModel();
    final runtime = runtime_factory.getRuntimeAIServiceForModel(defaultModel);
    if (defaultModel.startsWith('gpt-')) {
      impl = OpenAIAdapter(modelId: defaultModel, runtime: runtime);
    } else {
      impl = GeminiAdapter(modelId: defaultModel, runtime: runtime);
    }
  } else {
    final fallbackModel = Config.requireDefaultTextModel();
    final runtime = runtime_factory.getRuntimeAIServiceForModel(fallbackModel);
    if (fallbackModel.startsWith('gpt-')) {
      impl = OpenAIAdapter(modelId: fallbackModel, runtime: runtime);
    } else {
      impl = GeminiAdapter(modelId: fallbackModel, runtime: runtime);
    }
  }
  _aiServiceSingletons[key] = impl;
  return impl;
}

IProfileService getProfileServiceForProvider([final String? provider]) {
  if (provider != null && provider.trim().isNotEmpty) {
    final p = provider.toLowerCase();
    if (p == 'google' || p == 'gemini') {
      final imgModel = Config.getDefaultImageModel().isNotEmpty
          ? Config.getDefaultImageModel()
          : 'gpt-4o-mini';
      return ProfileAdapter(
        aiService: runtime_factory.getRuntimeAIServiceForModel(imgModel),
      );
    }
    if (p == 'openai') {
      final txtModel = Config.getDefaultTextModel().isNotEmpty
          ? Config.getDefaultTextModel()
          : 'gpt-4o-mini';
      return ProfileAdapter(
        aiService: runtime_factory.getRuntimeAIServiceForModel(txtModel),
      );
    }
    final fallbackImg = Config.getDefaultImageModel().isNotEmpty
        ? Config.getDefaultImageModel()
        : 'gpt-4o-mini';
    return ProfileAdapter(
      aiService: runtime_factory.getRuntimeAIServiceForModel(fallbackImg),
    );
  }

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

  if (resolved.isEmpty) resolved = 'google';

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

/// Application Services Factories
ChatApplicationService getChatApplicationService() => ChatApplicationService(
  repository: getChatRepository(),
  promptBuilder: PromptBuilderService(),
  fileOperations:
      const BasicFileOperationsService(), // Use the shared file operations service
  secureStorage: getSecureStorageService(),
);

ChatController getChatController() =>
    ChatController(chatService: getChatApplicationService());

VoiceCallApplicationService getVoiceCallApplicationService() {
  final callManager = CallManagerImpl();
  final audioManager = AudioManagerImpl();

  return VoiceCallApplicationService(
    startCallUseCase: StartCallUseCase(callManager),
    endCallUseCase: EndCallUseCase(
      callManager,
      getCallToChatCommunicationService(),
    ),
    handleIncomingCallUseCase: HandleIncomingCallUseCase(callManager),
    manageAudioUseCase: ManageAudioUseCase(audioManager),
  );
}

/// Domain Services Factories
ICallRepository getCallRepository() => InMemoryCallRepository();
IAudioManager getAudioManager() => FlutterAudioManager();
ICallManager getCallManager() => DefaultCallManager();
RealtimeTransportService getRealtimeTransportService() =>
    WebSocketRealtimeTransportService();
IRealtimeCallClient getRealtimeCallClient() => OpenAIRealtimeCallClient();
IProfileRepository getProfileRepository() => InMemoryProfileRepository();
AudioPlaybackService getAudioPlaybackService([final dynamic candidate]) =>
    getAudioPlayback(candidate);
IVadService getVadService() => VadService();

/// Infrastructure Services Factories
ISecureStorageService getSecureStorageService() =>
    const FlutterSecureStorageService();
IBackupService getBackupService() => BasicBackupService();
IPreferencesService getPreferencesService() => RealPreferencesService();
ILoggingService getLoggingService() => BasicLoggingService();
INetworkService getNetworkService() => BasicNetworkService();

CallSummaryService getCallSummaryService(final Map<String, dynamic> profile) =>
    CallSummaryService(
      profile: profile,
      aiService: getAIServiceForModel(Config.getDefaultTextModel()),
    );

IUIStateService getUIStateService() => BasicUIStateService();

/// Chat Domain Services Factories
IChatPromiseService getChatPromiseService() => BasicChatPromiseService();
IChatAudioUtilsService getChatAudioUtilsService() =>
    BasicChatAudioUtilsService();
IChatLoggingUtilsService getChatLoggingUtilsService() =>
    BasicChatLoggingUtilsService();
IChatPreferencesUtilsService getChatPreferencesUtilsService() =>
    BasicChatPreferencesUtilsService();
IChatDebouncedPersistenceService getChatDebouncedPersistenceService() =>
    BasicChatDebouncedPersistenceService();
IChatMessageQueueManager getChatMessageQueueManager() {
  // Usar la implementación completa que funciona correctamente
  return CompleteChatMessageQueueManager();
}

/// Communication Service Factory
ICallToChatCommunicationService getCallToChatCommunicationService() =>
    CallToChatCommunicationAdapter(getChatController());

/// Basic service implementations
class BasicSecureStorageService implements ISecureStorageService {
  @override
  Future<String?> read(final String key) async => null;
  @override
  Future<void> write(final String key, final String value) async {}
  @override
  Future<void> delete(final String key) async {}
  @override
  Future<bool> containsKey(final String key) async => false;
}

class BasicBackupService implements IBackupService {
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<void> uploadAfterChanges({
    required final Map<String, dynamic> profile,
    required final List<Map<String, dynamic>> messages,
    required final List<Map<String, dynamic>> timeline,
    required final bool isLinked,
  }) async {}
  @override
  Future<List<Map<String, dynamic>>> listBackups() async => [];
  @override
  Future<bool> refreshAccessToken() async => false;
}

class BasicPreferencesService implements IPreferencesService {
  @override
  Future<void> setSelectedModel(final String model) async {}
  @override
  Future<String?> getSelectedModel() async => null;
  @override
  Future<void> setSelectedAudioProvider(final String provider) async {}
  @override
  Future<String?> getSelectedAudioProvider() async => null;
  @override
  Future<void> setGoogleAccountInfo({
    final String? email,
    final String? avatar,
    final String? name,
    final bool? linked,
  }) async {}
  @override
  Future<void> clearGoogleAccountInfo() async {}
  @override
  Future<Map<String, dynamic>> getGoogleAccountInfo() async => {};
  @override
  Future<int?> getLastAutoBackupMs() async => null;
  @override
  Future<void> setLastAutoBackupMs(final int timestamp) async {}
  @override
  Future<String> getEvents() async => '[]';
  @override
  Future<void> setEvents(final String eventsJson) async {}
}

class BasicLoggingService implements ILoggingService {
  @override
  void debug(final String message, {final Object? error, final String? tag}) {}
  @override
  void info(final String message, {final Object? error, final String? tag}) {}
  @override
  void warning(
    final String message, {
    final Object? error,
    final String? tag,
  }) {}
  @override
  void error(
    final String message, {
    final Object? error,
    final StackTrace? stackTrace,
    final String? tag,
  }) {}
}

class BasicNetworkService implements INetworkService {
  @override
  Future<bool> hasInternetConnection() async => true;
}
