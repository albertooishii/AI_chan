import 'package:ai_chan/chat/domain/interfaces/i_chat_image_service.dart';
import 'package:ai_chan/shared/ai_providers/core/services/image_persistence_service.dart';

/// Infrastructure adapter implementing chat image service using shared image utilities.
/// Bridges domain interface with shared image processing functionality.
class ChatImageServiceAdapter implements IChatImageService {
  const ChatImageServiceAdapter();

  @override
  Future<String?> saveBase64ImageToFile(final String base64Data) async {
    return await ImagePersistenceService.instance.saveBase64Image(base64Data);
  }
}
