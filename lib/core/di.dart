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
import 'package:ai_chan/shared/domain/interfaces/i_ai_service.dart' as shared;

/// Factory functions and small helpers used across the app.
/// This file provides DI factories for the entire application.

/// Global initialization flag for Enhanced AI Runtime Provider
bool _enhancedSystemInitialized = false;

/// Initialize the Enhanced AI Provider System
/// Call this during app startup to enable the new provider system
Future<void> initializeEnhancedAISystem() async {
  if (_enhancedSystemInitialized) return;

  try {
    // The new AIProviderManager initializes automatically on first access
    _enhancedSystemInitialized = true;
    Log.i('Enhanced AI Provider System initialized successfully');
  } on Exception catch (e) {
    Log.w('Enhanced AI Provider System initialization failed: $e');
    Log.i('Continuing with runtime provider system');
    // Continue with runtime system
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

ICallSttService getSttService() =>
    _testSttOverride ?? const AIProviderSttAdapter();
ICallTtsService getTtsService() => const AIProviderTtsService();

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
    return _testSttOverride ?? const AIProviderSttAdapter();
  }
  if (p == 'openai') {
    return _testSttOverride ?? const AIProviderSttAdapter();
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
    return const AIProviderTtsService();
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

/// AI service factories - Use AIProviderManager.instance for dynamic provider access

IProfileService getProfileServiceForProvider([final String? provider]) {
  if (provider != null && provider.trim().isNotEmpty) {
    final p = provider.toLowerCase();
    if (p == 'google' || p == 'gemini') {
      return const ProfileAdapter();
    }
    if (p == 'openai') {
      return const ProfileAdapter();
    }
    return const ProfileAdapter();
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
    return const ProfileAdapter();
  }
  if (resolved == 'openai') {
    return const ProfileAdapter();
  }
  return const ProfileAdapter();
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
    CallSummaryService(profile: profile, aiService: getChatAIServiceAdapter());

IUIStateService getUIStateService() => BasicUIStateService();

/// Chat AI Service Factory
shared.IAIService getChatAIServiceAdapter() => const ChatAIServiceAdapter();

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
