import 'package:ai_chan/chat/domain/models/chat_result.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_manager.dart';
import 'package:ai_chan/chat/application/services/chat_message_service.dart';
import 'package:ai_chan/chat/application/mappers/message_factory.dart';
// ai_capability handled internally by provider manager

// Import new services
import '../services/message_image_processing_service.dart';
import '../services/message_audio_processing_service.dart';
import '../services/message_sanitization_service.dart';
import '../../domain/interfaces/i_chat_event_timeline_service.dart';
import '../../domain/interfaces/i_chat_logger.dart';

/// Send Message Use Case - Chat Application Layer
/// Orquesta el proceso completo de envío de mensaje usando servicios especializados
class SendMessageUseCase {
  SendMessageUseCase({
    final MessageImageProcessingService? imageService,
    final MessageAudioProcessingService? audioService,
    final MessageSanitizationService? sanitizationService,
    final IChatEventTimelineService? eventTimelineService,
  }) : _imageService = imageService ?? _createDefaultImageService(),
       _audioService = audioService ?? MessageAudioProcessingService(),
       _sanitizationService =
           sanitizationService ?? MessageSanitizationService(),
       _eventTimelineService =
           eventTimelineService ?? _DefaultEventTimelineService();

  // Use ChatMessageService to obtain domain Message objects
  late final ChatMessageService _chatMessageService = ChatMessageService(
    AIProviderManager.instance,
    MessageFactory(),
  );

  /// Creates default image service with stub dependencies
  static MessageImageProcessingService _createDefaultImageService() {
    return MessageImageProcessingService(_StubChatLogger());
  }

  final MessageImageProcessingService _imageService;
  final MessageAudioProcessingService _audioService;
  final MessageSanitizationService _sanitizationService;
  final IChatEventTimelineService _eventTimelineService;

  Future<SendMessageOutcome> sendChat({
    required final List<Message> recentMessages,
    required final SystemPrompt systemPromptObj,
    final String? imageBase64,
    final String? imageMimeType,
    final bool enableImageGeneration = false,
    final AiChanProfile? onboardingData,
    final Future<void> Function()? saveAll,
  }) async {
    // Convert messages to history format
    final history = _buildMessageHistory(recentMessages);

    // Capability is handled inside ChatMessageService/AIProviderManager

    // Use ChatMessageService to obtain a domain Message
    final message = await _chatMessageService.sendAndBuildMessage(
      history: history,
      systemPrompt: systemPromptObj,
      enableImageGeneration: enableImageGeneration,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
    );

    // If message text is empty, treat as failure
    if (message.text.trim().isEmpty) {
      // Build a synthetic AIResponse-like object for sanitization path
      final fakeResponse = AIResponse(text: '');
      return _handleFailedResponse(fakeResponse, 'auto-selected');
    }

    // Process image using the image service which now accepts domain Message
    final imageResult = await _imageService.processImageResponse(message);

    // Sanitize text content
    final String processedText = _imageService.sanitizeImageUrls(
      imageResult.processedText,
    );

    // Process audio tags
    final audioResult = _audioService.processAudioTags(processedText);

    // Build final result
    final chatResult = ChatResult(
      text: audioResult.cleanedText,
      isImage: imageResult.isImage,
      imagePath: imageResult.imagePath,
      prompt: message.image?.prompt ?? '',
      seed: message.image?.seed ?? '',
    );

    final assistantMessage = message;

    // Handle event processing if onboarding data provided
    AiChanProfile? updatedProfile;
    if (onboardingData != null) {
      updatedProfile = await _processEvents(
        recentMessages,
        chatResult,
        onboardingData,
        saveAll,
      );
    }

    return SendMessageOutcome(
      result: chatResult,
      assistantMessage: assistantMessage,
      ttsRequested: audioResult.ttsRequested,
      updatedProfile: updatedProfile,
    );
  }

  List<Map<String, String>> _buildMessageHistory(final List<Message> messages) {
    return messages
        .map(
          (final m) => {
            'role': m.sender == MessageSender.user
                ? 'user'
                : (m.sender == MessageSender.assistant
                      ? 'assistant'
                      : 'system'),
            'content': m.text,
            'datetime': m.dateTime.toIso8601String(),
          },
        )
        .toList();
  }

  SendMessageOutcome _handleFailedResponse(
    final AIResponse response,
    final String model,
  ) {
    // Check for API errors that should throw exceptions
    if (_sanitizationService.isApiError(response.text)) {
      throw Exception('API Error: ${response.text}');
    }

    final sanitized = _sanitizationService.sanitizeMessage(response.text);
    final chatResult = ChatResult(
      text: sanitized,
      isImage: false,
      imagePath: null,
      prompt: response.prompt,
      seed: response.seed,
    );

    final assistantMessage = _buildAssistantMessage(chatResult);

    return SendMessageOutcome(
      result: chatResult,
      assistantMessage: assistantMessage,
      ttsRequested: false,
    );
  }

  Message _buildAssistantMessage(final ChatResult chatResult) {
    return Message(
      text: chatResult.text,
      sender: MessageSender.assistant,
      dateTime: DateTime.now(),
      isImage: chatResult.isImage,
      image: chatResult.isImage
          ? AiImage(
              url: chatResult.imagePath ?? '',
              seed: chatResult.seed,
              prompt: chatResult.prompt,
            )
          : null,
      status: MessageStatus.read,
    );
  }

  Future<AiChanProfile?> _processEvents(
    final List<Message> recentMessages,
    final ChatResult chatResult,
    final AiChanProfile onboardingData,
    final Future<void> Function()? saveAll,
  ) async {
    try {
      return await _eventTimelineService.detectAndSaveEventAndSchedule(
        text: recentMessages.isNotEmpty ? recentMessages.last.text : '',
        textResponse: chatResult.text,
        onboardingData: onboardingData,
        saveAll: saveAll ?? () async {},
      );
    } on Exception catch (_) {
      return null;
    }
  }
}

/// Outcome returned by SendMessageUseCase which includes both the raw
/// ChatResult and a normalized assistant Message ready to be appended by the
/// caller. `ttsRequested` indicates whether the assistant message should trigger
/// TTS generation (i.e., contains paired [audio]...[/audio] tags).
class SendMessageOutcome {
  SendMessageOutcome({
    required this.result,
    required this.assistantMessage,
    required this.ttsRequested,
    this.updatedProfile,
  });
  final ChatResult result;
  final Message assistantMessage;
  final bool ttsRequested;
  final AiChanProfile? updatedProfile;
}

// Stub implementations for default constructor (avoid infrastructure dependencies)

// No-op image service stub removed; MessageImageProcessingService no longer needs it

/// Stub implementation that does nothing - safe fallback
class _StubChatLogger implements IChatLogger {
  @override
  void debug(final String message, {final String? tag}) {}

  @override
  void error(final String message, {final String? tag, final Object? error}) {}
}

/// Stub implementation that returns null - safe fallback
class _DefaultEventTimelineService implements IChatEventTimelineService {
  @override
  Future<dynamic> detectAndSaveEventAndSchedule({
    required final String text,
    required final String textResponse,
    required final dynamic onboardingData,
    required final Future<void> Function() saveAll,
  }) async => null;
}
