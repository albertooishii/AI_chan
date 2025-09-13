import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_logger.dart';

/// Service responsible for processing AI-generated images
/// Uses domain interfaces to maintain bounded context isolation.

class MessageImageProcessingService {
  MessageImageProcessingService(this._logger);
  final IChatLogger _logger;

  /// Process image data from domain Message. The AIProviderManager is
  /// responsible for persisting any base64 images and setting a filename on
  /// the returned Message.image.url. This service only maps that into a
  /// MessageImageResult and performs text sanitation.
  Future<MessageImageResult> processImageResponse(final Message message) async {
    final String text = message.text;

    // If manager already persisted the image, use the provided filename
    final imageUrl = message.image?.url ?? '';
    if (imageUrl.isNotEmpty) {
      return MessageImageResult(
        isImage: true,
        imagePath: imageUrl,
        processedText: text,
      );
    }

    // No image available
    return MessageImageResult(
      isImage: false,
      imagePath: null,
      processedText: text,
    );
  }

  /// Sanitize text that contains markdown images or URLs
  String sanitizeImageUrls(final String text) {
    final markdownImagePattern = RegExp(r'!\[.*?\]\((https?:\/\/.*?)\)');
    final urlInTextPattern = RegExp(r'https?:\/\/\S+\.(jpg|jpeg|png|webp|gif)');

    if (markdownImagePattern.hasMatch(text) ||
        urlInTextPattern.hasMatch(text)) {
      _logger.error(
        'La IA envió una imagen Markdown o URL en el texto',
        tag: 'AI_CHAT_RESPONSE',
      );
      return '$text\n[ERROR: La IA envió una imagen como enlace o Markdown. Pide la foto de nuevo.]';
    }

    return text;
  }
}

/// Result of image processing
class MessageImageResult {
  MessageImageResult({
    required this.isImage,
    required this.imagePath,
    required this.processedText,
  });
  final bool isImage;
  final String? imagePath;
  final String processedText;
}
