import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../models/system_prompt.dart';
import '../services/ai_service.dart';
import '../models/ai_response.dart';
import '../utils/image_utils.dart';

class AIChatResult {
  final String text;
  final bool isImage;
  final String? imagePath;
  final String? prompt;
  final String? seed;
  final String finalModelUsed;
  AIChatResult({
    required this.text,
    required this.isImage,
    required this.imagePath,
    required this.prompt,
    required this.seed,
    required this.finalModelUsed,
  });
}

/// Servicio que encapsula la lógica de enviar mensaje a la IA (incluye reintentos,
/// detección de generación de imagen y guardado de base64 a fichero).
class AiChatResponseService {
  static final RegExp _imageGenPattern = RegExp(r'tools.*(image_generation|Image Generation)', caseSensitive: false);
  static final RegExp _markdownImagePattern = RegExp(r'!\[.*?\]\((https?:\/\/.*?)\)');
  static final RegExp _urlInTextPattern = RegExp(r'https?:\/\/\S+\.(jpg|jpeg|png|webp|gif)');

  static int _extractWaitSeconds(String text) {
    final regex = RegExp(r'try again in ([\d\.]+)s');
    final match = regex.firstMatch(text);
    if (match != null && match.groupCount > 0) {
      return double.tryParse(match.group(1) ?? '8')?.round() ?? 8;
    }
    return 8;
  }

  static bool _hasValidText(AIResponse r) {
    final t = r.text.trim();
    if (t.isEmpty) return r.base64.isNotEmpty; // permitir solo imagen
    final lower = t.toLowerCase();
    if (lower.contains('error al conectar con la ia')) return false;
    if (lower.contains('"error"')) return false;
    return true;
  }

  static Future<AIChatResult> send({
    required List<Message> recentMessages,
    required SystemPrompt systemPromptObj,
    required String model,
    String? imageBase64,
    String? imageMimeType,
    required bool enableImageGeneration,
    int maxRetries = 3,
  }) async {
    String selected = model;

    // Helper local para convertir Message -> history entry
    Map<String, String> toHistoryEntry(Message m) {
      String content = m.text.trim();
      final imgPrompt = m.image?.prompt?.trim() ?? '';
      if (imgPrompt.isNotEmpty) {
        final caption = '[img_caption]$imgPrompt[/img_caption]';
        content = content.isEmpty ? caption : '$caption\n\n$content';
      }
      final role = m.sender == MessageSender.user
          ? 'user'
          : m.sender == MessageSender.assistant
          ? 'ia'
          : m.sender == MessageSender.system
          ? 'system'
          : 'unknown';
      return {"role": role, "content": content, "datetime": m.dateTime.toIso8601String()};
    }

    AIResponse response = await AIService.sendMessage(
      recentMessages.map(toHistoryEntry).toList(),
      systemPromptObj,
      model: selected,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      enableImageGeneration: enableImageGeneration,
    );

    // Si la respuesta sugiere tool image_generation y no es GPT ni Gemini, reenviar forzando gpt-4.1-mini
    if (_imageGenPattern.hasMatch(response.text)) {
      final lower = selected.toLowerCase();
      final isGpt = lower.startsWith('gpt-');
      final isGemini = lower.startsWith('gemini-');
      if (!isGpt && !isGemini) {
        selected = 'gpt-4.1-mini';
        response = await AIService.sendMessage(
          recentMessages.map(toHistoryEntry).toList(),
          systemPromptObj,
          model: selected,
          imageBase64: imageBase64,
          imageMimeType: imageMimeType,
          enableImageGeneration: true,
        );
      }
    }

    int retry = 0;
    while (!_hasValidText(response) && retry < maxRetries) {
      final waitSeconds = _extractWaitSeconds(response.text);
      await Future.delayed(Duration(seconds: waitSeconds));
      response = await AIService.sendMessage(
        recentMessages.map(toHistoryEntry).toList(),
        systemPromptObj,
        model: selected,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
        enableImageGeneration: enableImageGeneration,
      );
      retry++;
    }

    if (!_hasValidText(response)) {
      return AIChatResult(
        text: response.text,
        isImage: false,
        imagePath: null,
        prompt: response.prompt,
        seed: response.seed,
        finalModelUsed: selected,
      );
    }

    bool isImageResp = response.base64.isNotEmpty;
    String? imagePathResp;
    String textResponse = response.text;

    if (isImageResp) {
      // Validar que realmente sea base64 y no una URL
      final urlPattern = RegExp(r'^(https?:\/\/|file:|\/|[A-Za-z]:\\)');
      if (urlPattern.hasMatch(response.base64)) {
        debugPrint('[AI-chan][ERROR] La IA envió una URL/ruta en vez de imagen base64');
        textResponse += '\n[ERROR: La IA envió una URL/ruta en vez de imagen. Pide la foto de nuevo.]';
        isImageResp = false;
      } else {
        try {
          imagePathResp = await saveBase64ImageToFile(response.base64, prefix: 'img');
          if (imagePathResp == null) {
            debugPrint('[AI-chan][ERROR] No se pudo guardar la imagen localmente');
            isImageResp = false;
          }
        } catch (e) {
          debugPrint('[AI-chan][ERROR] Fallo guardando imagen: $e');
          isImageResp = false;
          imagePathResp = null;
        }
      }
    }

    if (_markdownImagePattern.hasMatch(textResponse) || _urlInTextPattern.hasMatch(textResponse)) {
      debugPrint('[AI-chan][ERROR] La IA envió una imagen Markdown o URL en el texto');
      textResponse += '\n[ERROR: La IA envió una imagen como enlace o Markdown. Pide la foto de nuevo.]';
    }

    return AIChatResult(
      text: textResponse,
      isImage: isImageResp,
      imagePath: imagePathResp,
      prompt: response.prompt,
      seed: response.seed,
      finalModelUsed: selected,
    );
  }
}
