import 'package:ai_chan/chat/domain/models/chat_result.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/services/ai_service.dart' show AIService;
import 'package:ai_chan/shared/domain/services/event_timeline_service.dart';
import 'package:ai_chan/shared/utils/image_utils.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/core/config.dart';

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
  SendMessageUseCase();

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

    // Preserve retries, image-detection and sanitization behavior when calling AIService.
    final RegExp imageGenPattern = RegExp(r'tools.*(image_generation|Image Generation)', caseSensitive: false);
    final RegExp markdownImagePattern = RegExp(r'!\[.*?\]\((https?:\/\/.*?)\)');
    final RegExp urlInTextPattern = RegExp(r'https?:\/\/\S+\.(jpg|jpeg|png|webp|gif)');

    int extractWaitSeconds(String text) {
      final regex = RegExp(r'try again in ([\d\.]+)s');
      final match = regex.firstMatch(text);
      if (match != null && match.groupCount > 0) {
        return double.tryParse(match.group(1) ?? '8')?.round() ?? 8;
      }
      return 8;
    }

    bool hasValidText(AIResponse r) {
      final t = r.text.trim();
      if (t.isEmpty) return r.base64.isNotEmpty; // allow only image
      final lower = t.toLowerCase();
      if (lower.contains('error al conectar con la ia')) return false;
      if (lower.contains('"error"')) return false;
      return true;
    }

    bool hasValidAllowedTagsStructure(String text) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return true;
      final tagToken = RegExp(r'\[/?([a-zA-Z0-9_]+)\]');
      final matches = tagToken.allMatches(trimmed).toList();
      final allowed = {'audio', 'img_caption', 'call', 'end_call', 'no_reply'};
      final tokens = <String>[];
      for (final m in matches) {
        final name = m.group(1);
        if (name == null) continue;
        tokens.add(name.toLowerCase());
      }
      for (final tk in tokens) {
        if (!allowed.contains(tk)) return false;
      }
      if (trimmed.contains('[call]') || trimmed.contains('[end_call]')) {
        final simpleTagPattern = RegExp(r'^\s*(\[(?:call|end_call)\]\s*\[/(?:call|end_call)\])\s*$');
        if (!simpleTagPattern.hasMatch(trimmed)) return false;
        return true;
      }
      final imgCaptionOpen = '[img_caption]';
      final imgCaptionClose = '[/img_caption]';
      if (trimmed.contains(imgCaptionOpen)) {
        final firstIdx = trimmed.indexOf(imgCaptionOpen);
        if (firstIdx != 0) return false;
        final closeIdx = trimmed.indexOf(imgCaptionClose, firstIdx + imgCaptionOpen.length);
        if (closeIdx < 0) return false;
        final after = trimmed.substring(closeIdx + imgCaptionClose.length).trimLeft();
        if (after.contains(imgCaptionOpen)) return false;
      }
      final audioOpen = '[audio]';
      final audioClose = '[/audio]';
      if (trimmed.contains(audioOpen)) {
        final openIdx = trimmed.indexOf(audioOpen);
        final closeIdx = trimmed.indexOf(audioClose, openIdx + audioOpen.length);
        if (closeIdx < 0) return false;
        final inner = trimmed.substring(openIdx + audioOpen.length, closeIdx).trim();
        if (inner.isEmpty) return false;
        if (inner.startsWith('[')) return false;
        final afterAudio = trimmed.substring(closeIdx + audioClose.length);
        if (afterAudio.contains(audioOpen)) return false;
      }
      bool balanced(String name) {
        final openCount = RegExp('\\[$name\\]').allMatches(trimmed).length;
        final closeCount = RegExp('\\[/$name\\]').allMatches(trimmed).length;
        return openCount == closeCount;
      }

      for (final name in ['audio', 'img_caption']) {
        if (!balanced(name)) return false;
      }
      return true;
    }

    // Map msgs to history required by AIService (List<Map<String,String>>)
    final history = msgs
        .map<Map<String, String>>((m) => {'role': m['role']!, 'content': m['content']!, 'datetime': m['datetime']!})
        .toList();

    String selected = model;
    AIResponse response = await AIService.sendMessage(
      history,
      systemPromptObj,
      model: selected,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      enableImageGeneration: enableImageGeneration,
    );

    // If the response suggests tool image_generation and model isn't GPT/Gemini, re-send with default image model
    if (imageGenPattern.hasMatch(response.text)) {
      final lower = selected.toLowerCase();
      final isGpt = lower.startsWith('gpt-');
      final isGemini = lower.startsWith('gemini-');
      if (!isGpt && !isGemini) {
        final cfgModel = Config.requireDefaultImageModel();
        selected = cfgModel;
        response = await AIService.sendMessage(
          history,
          systemPromptObj,
          model: selected,
          imageBase64: imageBase64,
          imageMimeType: imageMimeType,
          enableImageGeneration: true,
        );
      }
    }

    int retry = 0;
    while ((!hasValidText(response) || !hasValidAllowedTagsStructure(response.text)) && retry < 3) {
      final waitSeconds = extractWaitSeconds(response.text);
      await Future.delayed(Duration(seconds: waitSeconds));
      response = await AIService.sendMessage(
        history,
        systemPromptObj,
        model: selected,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
        enableImageGeneration: enableImageGeneration,
      );
      retry++;
    }

    if (!hasValidText(response) || !hasValidAllowedTagsStructure(response.text)) {
      String sanitized = response.text;
      sanitized = sanitized.replaceAll(RegExp(r'\[(?!/?(?:audio|img_caption|call|end_call)\b)[^\]\[]+\]'), '');
      final chatResultFail = ChatResult(
        text: sanitized,
        isImage: false,
        imagePath: null,
        prompt: response.prompt,
        seed: response.seed,
        finalModelUsed: selected,
      );
      // Build assistantMessage and return outcome
      final assistantMessageFail = Message(
        text: chatResultFail.text,
        sender: MessageSender.assistant,
        dateTime: DateTime.now(),
        isImage: chatResultFail.isImage,
        image: chatResultFail.isImage
            ? AiImage(url: chatResultFail.imagePath ?? '', seed: chatResultFail.seed, prompt: chatResultFail.prompt)
            : null,
        status: MessageStatus.read,
      );
      return SendMessageOutcome(
        result: chatResultFail,
        assistantMessage: assistantMessageFail,
        ttsRequested: false,
        updatedProfile: null,
      );
    }

    bool isImageResp = response.base64.isNotEmpty;
    String? imagePathResp;
    String textResponse = response.text;

    if (isImageResp) {
      final urlPattern = RegExp(r'^(https?:\/\/|file:|\/|[A-Za-z]:\\)');
      if (urlPattern.hasMatch(response.base64)) {
        Log.e('La IA envió una URL/ruta en vez de imagen base64', tag: 'AI_CHAT_RESPONSE');
        textResponse += '\n[ERROR: La IA envió una URL/ruta en vez de imagen. Pide la foto de nuevo.]';
        isImageResp = false;
      } else {
        try {
          imagePathResp = await saveBase64ImageToFile(response.base64, prefix: 'img');
          if (imagePathResp == null) {
            Log.e('No se pudo guardar la imagen localmente', tag: 'AI_CHAT_RESPONSE');
            isImageResp = false;
          }
        } catch (e) {
          Log.e('Fallo guardando imagen', tag: 'AI_CHAT_RESPONSE', error: e);
          isImageResp = false;
          imagePathResp = null;
        }
      }
    }

    if (markdownImagePattern.hasMatch(textResponse) || urlInTextPattern.hasMatch(textResponse)) {
      Log.e('La IA envió una imagen Markdown o URL en el texto', tag: 'AI_CHAT_RESPONSE');
      textResponse += '\n[ERROR: La IA envió una imagen como enlace o Markdown. Pide la foto de nuevo.]';
    }

    final chatResult = ChatResult(
      text: textResponse,
      isImage: isImageResp,
      imagePath: imagePathResp,
      prompt: response.prompt,
      seed: response.seed,
      finalModelUsed: selected,
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
