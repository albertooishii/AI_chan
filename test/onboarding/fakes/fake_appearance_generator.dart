import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/services/ai_service.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';

class FakeAppearanceGenerator extends IAAppearanceGenerator {
  @override
  Future<Map<String, dynamic>> generateAppearancePromptWithImage(
    AiChanProfile bio, {
    AIService? aiService,
    Future<String?> Function(String base64, {String prefix})? saveImageFunc,
  }) async {
    // return a simple appearance map with an avatar AiImage
    final avatar = AiImage(url: 'https://example.com/avatar.png', seed: '123', prompt: 'fake-prompt');
    return {
      'appearance': {'color': 'pink'},
      'avatar': avatar,
    };
  }
}
