import 'package:ai_chan/chat/domain/models/chat_result.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/interfaces/i_chat_response_service.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/shared/domain/services/event_timeline_service.dart';

/// Send Message Use Case - Chat Application Layer
/// Orquesta el proceso completo de envío de mensaje incluyendo:
/// - Validación del mensaje
/// - Adición a la conversación
/// - Procesamiento de respuesta de IA
/// - Actualización de estado
/// Caso de uso ligero para encapsular la llamada al servicio de respuesta.
/// La intención es mantener aquí la construcción del payload y el mapeo
/// del resultado a un `ChatResult`. La lógica de estado UI y persistencia
/// permanece en `ChatProvider`.
class SendMessageUseCase {
  final IChatResponseService? injectedService;

  SendMessageUseCase({this.injectedService});

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
    final msgs = recentMessages
        .map(
          (m) => {
            'role': m.sender == MessageSender.user ? 'user' : (m.sender == MessageSender.assistant ? 'ia' : 'system'),
            'content': m.text,
            'datetime': m.dateTime.toIso8601String(),
          },
        )
        .toList();

    final service = injectedService ?? di.getChatResponseService();

    final mapResult = await service.sendChat(
      msgs,
      options: {
        'systemPromptObj': systemPromptObj.toJson(),
        'model': model,
        'imageBase64': imageBase64,
        'imageMimeType': imageMimeType,
        'enableImageGeneration': enableImageGeneration,
      },
    );
    final chatResult = ChatResult(
      text: mapResult['text'] as String? ?? '',
      isImage: mapResult['isImage'] as bool? ?? false,
      imagePath: mapResult['imagePath'] as String?,
      prompt: mapResult['prompt'] as String?,
      seed: mapResult['seed'] as String?,
      finalModelUsed: mapResult['finalModelUsed'] as String? ?? model,
    );

    // Normalize [audio] tag and build assistant Message
    String assistantRawText = chatResult.text;
    final openTag = '[audio]';
    final closeTag = '[/audio]';
    final leftTrimmed = assistantRawText.trimLeft();
    final leftLower = leftTrimmed.toLowerCase();
    if (leftLower.startsWith(openTag)) {
      final afterTag = leftTrimmed.substring(openTag.length).trimLeft();
      final lowerAfter = afterTag.toLowerCase();
      if (lowerAfter.contains(closeTag)) {
        final endIdx = lowerAfter.indexOf(closeTag);
        final content = afterTag.substring(0, endIdx).trim();
        assistantRawText = '$openTag $content $closeTag';
      }
    }

    final assistantMessage = Message(
      text: assistantRawText,
      sender: MessageSender.assistant,
      dateTime: DateTime.now(),
      isImage: chatResult.isImage,
      image: chatResult.isImage
          ? AiImage(url: chatResult.imagePath ?? '', seed: chatResult.seed, prompt: chatResult.prompt)
          : null,
      status: MessageStatus.read,
    );

    // Run event detection/save if onboardingData provided. EventTimelineService
    // expects a saveAll callback. If none provided, pass a no-op.
    AiChanProfile? updatedProfile;
    if (onboardingData != null) {
      try {
        updatedProfile = await EventTimelineService.detectAndSaveEventAndSchedule(
          text: recentMessages.isNotEmpty ? recentMessages.last.text : '',
          textResponse: chatResult.text,
          onboardingData: onboardingData,
          saveAll: saveAll ?? () async {},
        );
      } catch (_) {
        updatedProfile = null;
      }
    }

    // Determine TTS request
    bool ttsRequested = false;
    final lower = assistantMessage.text.toLowerCase();
    final hasOpen = lower.contains(openTag);
    final hasClose = lower.contains(closeTag);
    if (hasOpen && hasClose) {
      final start = lower.indexOf(openTag) + openTag.length;
      final end = lower.indexOf(closeTag, start);
      if (end > start) {
        final inner = assistantMessage.text.substring(start, end).trim();
        if (inner.isNotEmpty) ttsRequested = true;
      }
    }

    return SendMessageOutcome(
      result: chatResult,
      assistantMessage: assistantMessage,
      ttsRequested: ttsRequested,
      updatedProfile: updatedProfile,
    );
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
