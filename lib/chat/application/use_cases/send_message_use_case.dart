import 'package:ai_chan/chat/domain/models/chat_result.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/domain/services/event_timeline_service.dart';
import 'package:ai_chan/core/config.dart';

// Import new services
import '../services/message_retry_service.dart';
import '../services/message_image_processing_service.dart';
import '../services/message_audio_processing_service.dart';
import '../services/message_sanitization_service.dart';

/// Send Message Use Case - Chat Application Layer
/// Orquesta el proceso completo de envío de mensaje usando servicios especializados
class SendMessageUseCase {
  final MessageRetryService _retryService;
  final MessageImageProcessingService _imageService;
  final MessageAudioProcessingService _audioService;
  final MessageSanitizationService _sanitizationService;

  SendMessageUseCase({
    MessageRetryService? retryService,
    MessageImageProcessingService? imageService,
    MessageAudioProcessingService? audioService,
    MessageSanitizationService? sanitizationService,
  }) : _retryService = retryService ?? MessageRetryService(),
       _imageService = imageService ?? MessageImageProcessingService(),
       _audioService = audioService ?? MessageAudioProcessingService(),
       _sanitizationService =
           sanitizationService ?? MessageSanitizationService();

  Future<SendMessageOutcome> sendChat({
    required List<Message> recentMessages,
    required SystemPrompt systemPromptObj,
    required String model,
    String? imageBase64,
    String? imageMimeType,
    bool enableImageGeneration = false,
    AiChanProfile? onboardingData,
    Future<void> Function()? saveAll,
  }) async {
    // Convert messages to history format
    final history = _buildMessageHistory(recentMessages);

    // Handle image generation model switching
    String selectedModel = await _selectOptimalModel(
      model,
      enableImageGeneration,
    );

    // Send message with retry logic
    final response = await _retryService.sendWithRetries(
      history: history,
      systemPrompt: systemPromptObj,
      model: selectedModel,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      enableImageGeneration: enableImageGeneration,
    );

    // Handle failed responses
    if (!_retryService.hasValidText(response) ||
        !_retryService.hasValidAllowedTagsStructure(response.text)) {
      return _handleFailedResponse(response, selectedModel);
    }

    // Process image response
    final imageResult = await _imageService.processImageResponse(response);

    // Sanitize text content
    String processedText = _imageService.sanitizeImageUrls(
      imageResult.processedText,
    );

    // Process audio tags
    final audioResult = _audioService.processAudioTags(processedText);

    // Build final result
    final chatResult = ChatResult(
      text: audioResult.cleanedText,
      isImage: imageResult.isImage,
      imagePath: imageResult.imagePath,
      prompt: response.prompt,
      seed: response.seed,
      finalModelUsed: selectedModel,
    );

    final assistantMessage = _buildAssistantMessage(chatResult);

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

  List<Map<String, String>> _buildMessageHistory(List<Message> messages) {
    return messages
        .map(
          (m) => {
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

  Future<String> _selectOptimalModel(
    String model,
    bool enableImageGeneration,
  ) async {
    String selected = model;

    // Check if we need to switch to image-capable model
    if (enableImageGeneration) {
      final lower = selected.toLowerCase();
      final isGpt = lower.startsWith('gpt-');
      final isGemini = lower.startsWith('gemini-');
      if (!isGpt && !isGemini) {
        selected = Config.requireDefaultImageModel();
      }
    }

    return selected;
  }

  SendMessageOutcome _handleFailedResponse(AIResponse response, String model) {
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
      finalModelUsed: model,
    );

    final assistantMessage = _buildAssistantMessage(chatResult);

    return SendMessageOutcome(
      result: chatResult,
      assistantMessage: assistantMessage,
      ttsRequested: false,
      updatedProfile: null,
    );
  }

  Message _buildAssistantMessage(ChatResult chatResult) {
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
    List<Message> recentMessages,
    ChatResult chatResult,
    AiChanProfile onboardingData,
    Future<void> Function()? saveAll,
  ) async {
    try {
      return await EventTimelineService.detectAndSaveEventAndSchedule(
        text: recentMessages.isNotEmpty ? recentMessages.last.text : '',
        textResponse: chatResult.text,
        onboardingData: onboardingData,
        saveAll: saveAll ?? () async {},
      );
    } catch (_) {
      return null;
    }
  }
}

/// Outcome returned by SendMessageUseCase which includes both the raw
/// ChatResult and a normalized assistant Message ready to be appended by the
/// caller. `ttsRequested` indicates whether the assistant message should trigger
/// TTS generation (i.e., contains paired [audio]...[/audio] tags).
class SendMessageOutcome {
  final ChatResult result;
  final Message assistantMessage;
  final bool ttsRequested;
  final AiChanProfile? updatedProfile;

  SendMessageOutcome({
    required this.result,
    required this.assistantMessage,
    required this.ttsRequested,
    this.updatedProfile,
  });
}
