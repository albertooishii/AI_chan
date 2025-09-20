import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// AI Chan - Barrel Imports (Bounded Contexts) - preferred for all imports
import 'package:ai_chan/chat.dart';
import 'package:ai_chan/voice.dart';
import 'package:ai_chan/onboarding.dart';
import 'package:ai_chan/shared.dart' as shared;

// Main app imports
import 'package:ai_chan/main.dart' show navigatorKey;

CentralizedTtsService getCentralizedTtsService() =>
    CentralizedTtsService.instance;
CentralizedSttService getCentralizedSttService() =>
    CentralizedSttService.instance;

/// Factory functions and small helpers used across the app.
/// This file provides DI factories for the entire application.

/// Global initialization flag for Enhanced AI Runtime Provider

IChatRepository getChatRepository() => LocalChatRepository();

/// Factory for shared chat repository - allows cross-context usage
ISharedChatRepository getSharedChatRepository() => SharedChatRepositoryImpl();

/// Factory for file service - handles file operations
IFileService getFileService() => FileService();

/// Factory for File UI Service - DDD compliance for presentation layer
FileUIService getFileUIService() =>
    const FileUIService(BasicChatFileOperationsService());

/// Factory for navigation service - handles cross-context navigation
NavigationService getNavigationService() => NavigationService(navigatorKey);

/// TTS Voice Management Service Factory
TtsVoiceManagementService getTtsVoiceManagementService() =>
    TtsVoiceManagementService(providerManager: AIProviderManager.instance);

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

/// ✅ NUEVO: Migración a RealtimeService Unificado
///
/// Obtiene cliente realtime usando el sistema unificado de providers
/// En lugar del registry manual, usa el AIProviderRegistry dinámico

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
  fileOperations: const BasicChatFileOperationsService(),
  secureStorage: getSecureStorageService(),
  audioService: BasicAudioChatService(),
);

ChatController getChatController() =>
    ChatController(chatService: getChatApplicationService());

// 🎯 Voice Services (Legacy functions redirected to new Voice bounded context)
dynamic getTtsService() => getDynamicTtsService();
dynamic getTtsServiceForProvider(final String provider) =>
    getDynamicTtsService();

dynamic getSttServiceForProvider(final String provider) =>
    getDynamicSttService();

// 🎯 Voice Bounded Context Services

VoiceApplicationService getVoiceApplicationService() =>
    VoiceApplicationService(useCase: getManageVoiceSessionUseCase());
IToneService getToneService() => ToneService.instance;
IVoiceConversationService getVoiceConversationService() =>
    VoiceConversationService.instance;

// Temporary workaround - use dynamic to avoid type conflicts
ManageVoiceSessionUseCase getManageVoiceSessionUseCase() =>
    ManageVoiceSessionUseCase(
      ttsService: getCentralizedTtsService(),
      sttService: getCentralizedSttService(),
    );

dynamic getDynamicTtsService() => getCentralizedTtsService();
dynamic getDynamicSttService() => getCentralizedSttService();

// 🎯 Legacy Audio Services (Legacy functions for TTS compatibility)
AudioPlaybackService getAudioPlaybackService() => AudioPlaybackServiceAdapter();

// 🎯 Legacy Test Support Functions (for compatibility)

void setTestAudioPlaybackOverride(final dynamic service) {
  // No-op: Legacy Call tests are being eliminated
}

/// Infrastructure Services Factories

ISecureStorageService getSecureStorageService() {
  // Use FlutterSecureStorage directly instead of wrapper
  const storage = FlutterSecureStorage();
  return const _FlutterSecureStorageAdapter(storage);
}

/// Direct adapter for FlutterSecureStorage without unnecessary abstraction
class _FlutterSecureStorageAdapter implements ISecureStorageService {
  const _FlutterSecureStorageAdapter(this._storage);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(final String key) async {
    try {
      return await _storage.read(key: key);
    } on Exception {
      return null;
    }
  }

  @override
  Future<void> write(final String key, final String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on Exception {
      // Silently fail for non-critical operations
    }
  }

  @override
  Future<void> delete(final String key) async {
    try {
      await _storage.delete(key: key);
    } on Exception {
      // Silently fail for non-critical operations
    }
  }

  @override
  Future<bool> containsKey(final String key) async {
    try {
      return await _storage.containsKey(key: key);
    } on Exception {
      return false;
    }
  }
}

BasicUIStateService getUIStateService() => BasicUIStateService();

/// Chat AI Service Factory
shared.IAIService getChatAIServiceAdapter() {
  final service = ChatMessageService(
    AIProviderManager.instance,
    MessageFactory(),
  );
  return ChatAIServiceAdapter(service);
}

/// Onboarding Biography Generation Use Case Factory - moved from OnboardingDI to eliminate presentation→infrastructure violations
Future<BiographyGenerationUseCase> getBiographyGenerationUseCase() async {
  // Import onboarding dependencies locally to avoid circular imports
  return BiographyGenerationUseCase(
    profileService: await getProfileServiceForProvider(),
    chatExportService: getSharedChatRepository(),
    onboardingPersistenceService: OnboardingPersistenceServiceAdapter(),
  );
}
