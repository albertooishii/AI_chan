import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'package:ai_chan/services/openai_service.dart';

class OpenAISttAdapter implements ISttService {
  final OpenAIService _impl = OpenAIService();

  @override
  Future<String?> transcribeAudio(String path) async {
    try {
      return await _impl.transcribeAudio(path);
    } catch (e) {
      // Let caller handle logging/error
      return null;
    }
  }
}
