// lib/core/di.dart
// Dependency Injection Container for AI Chan
// Clean imports using barrel exports where possible for better maintainability

// Dart Imports
import 'dart:typed_data';

// AI Chan - Barrel Imports (DDD Bounded Contexts)
import 'package:ai_chan/chat.dart';
import 'package:ai_chan/call.dart';
import 'package:ai_chan/core.dart';
import 'package:ai_chan/onboarding.dart';

// Import specific services that need DI
import 'package:ai_chan/chat/domain/interfaces/i_tts_voice_management_service.dart';
import 'package:ai_chan/chat/application/services/tts_voice_management_service.dart';

/// Factory functions and small helpers used across the app.
/// This file provides DI factories for the entire application.

/// Global initialization flag for Enhanced AI Runtime Provider
bool _enhancedSystemInitialized = false;

/// Initialize the Enhanced AI Provider System
/// Call this during app startup to enable the new provider system
Future<void> initializeEnhancedAISystem() async {
  if (_enhancedSystemInitialized) return;

  try {
    await EnhancedAIRuntimeProvider.initialize();
    _enhancedSystemInitialized = true;
    Log.i('Enhanced AI Provider System initialized successfully');
  } on Exception catch (e) {
    Log.w('Enhanced AI Provider System initialization failed: $e');
    Log.i('Falling back to legacy runtime system');
    // Continue with legacy system
  }
}

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

/// AI Service factory with singleton pattern - Enhanced AI system only
final Map<String, IAIService> _aiServiceSingletons = {};

/// Enhanced AI Service that implements IAIService interface
class _EnhancedAIService implements IAIService {
  _EnhancedAIService(this.modelId);
  final String modelId;

  @override
  Future<List<String>> getAvailableModels() async {
    try {
      await initializeEnhancedAISystem();
      final service = await EnhancedAIRuntimeProvider.getAIServiceForModel(
        modelId,
      );
      return await service.getAvailableModels();
    } on Exception {
      return [modelId];
    }
  }

  @override
  Future<Map<String, dynamic>> sendMessage({
    required final List<Map<String, dynamic>> messages,
    final Map<String, dynamic>? options,
  }) async {
    try {
      await initializeEnhancedAISystem();
      final service = await EnhancedAIRuntimeProvider.getAIServiceForModel(
        modelId,
      );

      final model = options?['model'] as String?;
      final imageBase64 = options?['imageBase64'] as String?;
      final imageMimeType = options?['imageMimeType'] as String?;
      final enableImageGeneration =
          options?['enableImageGeneration'] as bool? ?? false;

      final response = await service.sendMessageImpl(
        messages.cast<Map<String, String>>(),
        options?['systemPromptObj'] as dynamic,
        model: model,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
        enableImageGeneration: enableImageGeneration,
      );

      // Convert AIResponse to legacy format
      return response.toJson();
    } on Exception catch (e) {
      Log.e('Enhanced AI Service failed: $e');
      return {'text': 'AI system temporarily unavailable. Please try again.'};
    }
  }

  @override
  Future<String?> textToSpeech(
    final String text, {
    final String voice = '',
    final Map<String, dynamic>? options,
  }) async {
    // TTS not implemented in Enhanced AI yet - return null for now
    return null;
  }
}

IAIService getAIServiceForModel(final String modelId) {
  final normalized = modelId.trim().toLowerCase();
  String key = normalized;
  if (key.isEmpty) key = 'default';
  if (_aiServiceSingletons.containsKey(key)) return _aiServiceSingletons[key]!;

  // Create Enhanced AI Service directly - no more adapters
  final effectiveModelId = normalized.isEmpty
      ? Config.requireDefaultTextModel()
      : normalized;
  final impl = _EnhancedAIService(effectiveModelId);

  _aiServiceSingletons[key] = impl;
  return impl;
}

/// Create a synchronous Enhanced AI service adapter for runtime AI services
dynamic _createEnhancedRuntimeServiceSync(final String modelId) {
  return _EnhancedRuntimeServiceAdapter(modelId);
}

/// Runtime service adapter that bridges to Enhanced AI system
class _EnhancedRuntimeServiceAdapter extends AIService {
  _EnhancedRuntimeServiceAdapter(this.modelId);
  final String modelId;

  @override
  Future<List<String>> getAvailableModels() async {
    try {
      await initializeEnhancedAISystem();
      final service = await EnhancedAIRuntimeProvider.getAIServiceForModel(
        modelId,
      );
      return await service.getAvailableModels();
    } on Exception {
      return [modelId];
    }
  }

  @override
  Future<AIResponse> sendMessageImpl(
    final List<Map<String, String>> history,
    final SystemPrompt systemPrompt, {
    final String? model,
    final String? imageBase64,
    final String? imageMimeType,
    final bool enableImageGeneration = false,
  }) async {
    try {
      await initializeEnhancedAISystem();
      final service = await EnhancedAIRuntimeProvider.getAIServiceForModel(
        model ?? modelId,
      );
      return await service.sendMessageImpl(
        history,
        systemPrompt,
        model: model,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
        enableImageGeneration: enableImageGeneration,
      );
    } on Exception catch (e) {
      Log.w('Enhanced AI Runtime error for model ${model ?? modelId}: $e');
      rethrow;
    }
  }
}

IProfileService getProfileServiceForProvider([final String? provider]) {
  if (provider != null && provider.trim().isNotEmpty) {
    final p = provider.toLowerCase();
    if (p == 'google' || p == 'gemini') {
      final imgModel = Config.getDefaultImageModel().isNotEmpty
          ? Config.getDefaultImageModel()
          : 'gpt-4o-mini';
      return ProfileAdapter(
        aiService: _createEnhancedRuntimeServiceSync(imgModel),
      );
    }
    if (p == 'openai') {
      final txtModel = Config.getDefaultTextModel().isNotEmpty
          ? Config.getDefaultTextModel()
          : 'gpt-4o-mini';
      return ProfileAdapter(
        aiService: _createEnhancedRuntimeServiceSync(txtModel),
      );
    }
    final fallbackImg = Config.getDefaultImageModel().isNotEmpty
        ? Config.getDefaultImageModel()
        : 'gpt-4o-mini';
    return ProfileAdapter(
      aiService: _createEnhancedRuntimeServiceSync(fallbackImg),
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
      aiService: _createEnhancedRuntimeServiceSync(
        Config.requireDefaultImageModel(),
      ),
    );
  }
  if (resolved == 'openai') {
    return ProfileAdapter(
      aiService: _createEnhancedRuntimeServiceSync(
        Config.requireDefaultTextModel(),
      ),
    );
  }
  return ProfileAdapter(
    aiService: _createEnhancedRuntimeServiceSync(
      Config.requireDefaultImageModel(),
    ),
  );
}

/// Application Services Factories
ChatApplicationService getChatApplicationService() => ChatApplicationService(
  chatAIService: const ChatAIServiceAdapter(),
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

/// Chat AI Service Factory
IChatAIService getChatAIServiceAdapter() => const ChatAIServiceAdapter();

/// Chat Domain Services Factories
IChatPromiseService getChatPromiseService() => BasicChatPromiseService();
IChatAudioUtilsService getChatAudioUtilsService() =>
    BasicChatAudioUtilsService();
IChatLoggingUtilsService getChatLoggingUtilsService() =>
    BasicChatLoggingUtilsService();
BasicChatPreferencesUtilsService getChatPreferencesUtilsService() =>
    BasicChatPreferencesUtilsService();
IChatDebouncedPersistenceService getChatDebouncedPersistenceService() =>
    BasicChatDebouncedPersistenceService();
IChatMessageQueueManager getChatMessageQueueManager() {
  // Usar la implementación completa que funciona correctamente
  return CompleteChatMessageQueueManager();
}

/// TTS Voice Management Service Factory
ITtsVoiceManagementService getTtsVoiceManagementService() =>
    TtsVoiceManagementService();

/// Communication Service Factory
ICallToChatCommunicationService getCallToChatCommunicationService() =>
    CallToChatCommunicationAdapter(getChatController());
