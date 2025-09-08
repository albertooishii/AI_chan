import 'package:ai_chan/chat/domain/interfaces/i_chat_image_service.dart';
import 'package:ai_chan/shared/utils/image_utils.dart' as image_utils;

/// Infrastructure adapter implementing chat image service using shared image utilities.
/// Bridges domain interface with shared image processing functionality.
class ChatImageServiceAdapter implements IChatImageService {
  const ChatImageServiceAdapter();

  @override
  Future<String?> saveBase64ImageToFile(final String base64Data) async {
    return await image_utils.saveBase64ImageToFile(base64Data);
  }
}
