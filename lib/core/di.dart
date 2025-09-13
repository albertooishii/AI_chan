import 'dart:typed_data';

// AI Chan - Barrel Imports (Bounded Contexts)
import 'package:ai_chan/chat.dart';
import 'package:ai_chan/voice.dart'; // 🔥 NEW: Voice bounded context
import 'package:ai_chan/core.dart';
import 'package:ai_chan/onboarding.dart';
import 'package:ai_chan/shared.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_manager.dart';
import 'package:ai_chan/chat/application/services/chat_message_service.dart';
import 'package:ai_chan/chat/application/mappers/message_factory.dart';

// Import specific services that need DI
import 'package:ai_chan/chat/domain/interfaces/i_tts_voice_management_service.dart';
import 'package:ai_chan/shared/infrastructure/adapters/audio_playback_service_adapter.dart';
import 'package:ai_chan/shared/domain/interfaces/i_ai_service.dart' as shared;
import 'package:ai_chan/shared/ai_providers/core/services/audio/centralized_tts_service.dart';
import 'package:ai_chan/shared/ai_providers/core/services/audio/centralized_stt_service.dart';

CentralizedTtsService getCentralizedTtsService() =>
    CentralizedTtsService.instance;
CentralizedSttService getCentralizedSttService() =>
    CentralizedSttService.instance;

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

/// Factory for audio playback (legacy compatibility)
AudioPlayback getAudioPlayback([final dynamic candidate]) =>
    AudioPlayback.adapt(candidate);

/// 🔥 Realtime client registry for enhanced AI providers
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

/// ✅ NUEVO: Migración a RealtimeService Unificado
///
/// Obtiene cliente realtime usando el sistema unificado de providers
/// En lugar del registry manual, usa el AIProviderRegistry dinámico
Future<IRealtimeClient> getRealtimeClientForProvider(
  final String provider, {
  final String? model,
  final void Function(String)? onText,
  final void Function(Uint8List)? onAudio,
  final void Function()? onCompleted,
  final void Function(String)? onError,
  final void Function(String)? onUserTranscription,
}) async {
  // Mantener soporte para tests
  if (_testRealtimeClientFactory != null) {
    return _testRealtimeClientFactory!(
      provider,
      model: model,
      onText: onText,
      onAudio: onAudio,
      onCompleted: onCompleted,
      onError: onError != null
          ? (final Object error) => onError(error.toString())
          : null,
      onUserTranscription: onUserTranscription,
    );
  }

  try {
    // ✨ USA REALTIME SERVICE configurado dinámicamente
    return await RealtimeService.getConfiguredRealtimeClient(
      onText: onText,
      onAudio: onAudio != null
          ? (final List<int> audio) => onAudio(Uint8List.fromList(audio))
          : null,
      onCompleted: onCompleted,
      onError: onError != null ? (final String error) => onError(error) : null,
      onUserTranscription: onUserTranscription,
      additionalParams: model != null ? {'model': model} : {},
    );
  } on Exception catch (e) {
    Log.w('[DI] Failed to get realtime client for provider $provider: $e');
    return NotSupportedRealtimeClient(provider);
  }
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
    final String voice = '', // Dinámico del provider configurado
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

Future<IProfileService> getProfileServiceForProvider([
  final String? provider,
]) async {
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

  final defaultTextModel = await AIProviderManager.instance
      .getDefaultTextModel();
  final defaultImageModel = await AIProviderManager.instance
      .getDefaultImageModel();
  String resolved = '';
  final modelToCheck =
      ((defaultTextModel?.isNotEmpty == true
                  ? defaultTextModel!
                  : defaultImageModel) ??
              '')
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
  repository: getChatRepository(),
  promptBuilder: PromptBuilderService(),
  fileOperations: const BasicFileOperationsService(),
  secureStorage: getSecureStorageService(),
);

ChatController getChatController() =>
    ChatController(chatService: getChatApplicationService());

// 🎯 Voice Services (Legacy functions redirected to new Voice bounded context)
dynamic getTtsService() => getDynamicTtsService();
dynamic getTtsServiceForProvider(final String provider) =>
    getDynamicTtsService();
dynamic getSttService() => getDynamicSttService();
dynamic getSttServiceForProvider(final String provider) =>
    getDynamicSttService();

// 🎯 Voice Bounded Context Services
VoiceController getVoiceController() =>
    VoiceController(getVoiceApplicationService());
VoiceApplicationService getVoiceApplicationService() =>
    VoiceApplicationService(useCase: getManageVoiceSessionUseCase());
IToneService getToneService() => ToneService.instance;
IVoiceConversationService getVoiceConversationService() =>
    VoiceConversationService.instance;

// Temporary workaround - use dynamic to avoid type conflicts
ManageVoiceSessionUseCase getManageVoiceSessionUseCase() =>
    ManageVoiceSessionUseCase(
      ttsService: getDynamicTtsService() as ITextToSpeechService,
      sttService: getDynamicSttService() as ISpeechToTextService,
    );
VoiceSessionOrchestrator getVoiceSessionOrchestrator() =>
    VoiceSessionOrchestrator(
      ttsService: getDynamicTtsService() as ITextToSpeechService,
      sttService: getDynamicSttService() as ISpeechToTextService,
    );
dynamic getDynamicTtsService() => getCentralizedTtsService();
dynamic getDynamicSttService() => getCentralizedSttService();

// 🎯 Legacy Audio Services (Legacy functions for TTS compatibility)
AudioPlaybackService getAudioPlaybackService() => AudioPlaybackServiceAdapter();

// 🎯 Legacy Test Support Functions (for compatibility)
void setTestSttOverride(final dynamic service) {
  // No-op: Legacy Call tests are being eliminated
}

void setTestAudioPlaybackOverride(final dynamic service) {
  // No-op: Legacy Call tests are being eliminated
}

/// Infrastructure Services Factories
ISecureStorageService getSecureStorageService() =>
    const FlutterSecureStorageService();
IBackupService getBackupService() => BasicBackupService();
IPreferencesService getPreferencesService() => RealPreferencesService();
ILoggingService getLoggingService() => BasicLoggingService();
INetworkService getNetworkService() => BasicNetworkService();
IUIStateService getUIStateService() => BasicUIStateService();

/// Chat AI Service Factory
shared.IAIService getChatAIServiceAdapter() {
  final service = ChatMessageService(
    AIProviderManager.instance,
    MessageFactory(),
  );
  return ChatAIServiceAdapter(service);
}

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
  return CompleteChatMessageQueueManager();
}

/// TTS Voice Management Service Factory
ITtsVoiceManagementService getTtsVoiceManagementService() =>
    TtsVoiceManagementServiceAdapter();
