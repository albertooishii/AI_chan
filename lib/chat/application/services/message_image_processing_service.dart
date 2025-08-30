import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/image_utils.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Service responsible for processing AI-generated images
class MessageImageProcessingService {
  /// Process image response from AI and save it locally
  Future<MessageImageResult> processImageResponse(AIResponse response) async {
    if (response.base64.isEmpty) {
      return MessageImageResult(isImage: false, imagePath: null, processedText: response.text);
    }

    // Check if AI sent URL/path instead of base64
    final urlPattern = RegExp(r'^(https?:\/\/|file:|\/|[A-Za-z]:\\)');
    if (urlPattern.hasMatch(response.base64)) {
      Log.e('La IA envió una URL/ruta en vez de imagen base64', tag: 'AI_CHAT_RESPONSE');
      return MessageImageResult(
        isImage: false,
        imagePath: null,
        processedText: '${response.text}\n[ERROR: La IA envió una URL/ruta en vez de imagen. Pide la foto de nuevo.]',
      );
    }

    try {
      final imagePath = await saveBase64ImageToFile(response.base64, prefix: 'img');
      if (imagePath == null) {
        Log.e('No se pudo guardar la imagen localmente', tag: 'AI_CHAT_RESPONSE');
        return MessageImageResult(isImage: false, imagePath: null, processedText: response.text);
      }

      return MessageImageResult(isImage: true, imagePath: imagePath, processedText: response.text);
    } catch (e) {
      Log.e('Fallo guardando imagen', tag: 'AI_CHAT_RESPONSE', error: e);
      return MessageImageResult(isImage: false, imagePath: null, processedText: response.text);
    }
  }

  /// Sanitize text that contains markdown images or URLs
  String sanitizeImageUrls(String text) {
    final markdownImagePattern = RegExp(r'!\[.*?\]\((https?:\/\/.*?)\)');
    final urlInTextPattern = RegExp(r'https?:\/\/\S+\.(jpg|jpeg|png|webp|gif)');

    if (markdownImagePattern.hasMatch(text) || urlInTextPattern.hasMatch(text)) {
      Log.e('La IA envió una imagen Markdown o URL en el texto', tag: 'AI_CHAT_RESPONSE');
      return '$text\n[ERROR: La IA envió una imagen como enlace o Markdown. Pide la foto de nuevo.]';
    }

    return text;
  }
}

/// Result of image processing
class MessageImageResult {
  final bool isImage;
  final String? imagePath;
  final String processedText;

  MessageImageResult({required this.isImage, required this.imagePath, required this.processedText});
}
