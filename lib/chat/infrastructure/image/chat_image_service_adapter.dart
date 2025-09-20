import 'package:ai_chan/chat.dart';
import 'package:ai_chan/shared.dart';

/// Infrastructure adapter implementing chat image service using shared image utilities.
/// Bridges domain interface with shared image processing functionality.
class ChatImageServiceAdapter implements IChatImageService {
  const ChatImageServiceAdapter();

  @override
  Future<String?> saveBase64ImageToFile(final String base64Data) async {
    return await ImagePersistenceService.instance.saveBase64Image(base64Data);
  }
}
