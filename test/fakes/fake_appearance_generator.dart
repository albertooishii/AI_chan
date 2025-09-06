import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';
import 'package:ai_chan/shared/services/ai_service.dart';

class FakeAppearanceGenerator extends IAAppearanceGenerator {
  @override
  Future<Map<String, dynamic>> generateAppearanceFromBiography(
    final AiChanProfile bio, {
    final AIService? aiService,
    final Future<String?> Function(String base64, {String prefix})?
    saveImageFunc,
  }) async {
    return {'color': 'pink'};
  }
}
