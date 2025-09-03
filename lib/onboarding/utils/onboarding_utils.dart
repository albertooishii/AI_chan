import 'package:ai_chan/shared/services/ai_service.dart' as ai_service;
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/services/prompt_builder.dart';

/// Utilidades específicas para el proceso de onboarding
class OnboardingUtils {
  /// Genera sugerencia para "cómo nos conocimos" basada en los datos recopilados
  static Future<String> generateMeetStoryFromContext({
    required String userName,
    required String aiName,
    String? userCountry,
    String? aiCountry,
    DateTime? userBirthday,
  }) async {
    final prompt = PromptBuilder.buildMeetStoryPrompt(
      userName: userName,
      aiName: aiName,
      userCountry: userCountry,
      aiCountry: aiCountry,
    );

    final profile = AiChanProfile(
      userName: userName,
      aiName: aiName,
      userBirthday: userBirthday ?? DateTime.now(),
      aiBirthday: DateTime.now(),
      biography: {},
      appearance: {},
      timeline: [],
    );

    final systemPrompt = SystemPrompt(
      profile: profile,
      dateTime: DateTime.now(),
      instructions: PromptBuilder.buildStorySystemPrompt(),
    );

    final history = [
      {
        'role': 'user',
        'content': prompt,
        'datetime': DateTime.now().toIso8601String(),
      },
    ];

    final response = await ai_service.AIService.sendMessage(
      history,
      systemPrompt,
      model: Config.getDefaultTextModel(),
    );

    return response.text.trim();
  }
}
