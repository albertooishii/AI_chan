import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_manager.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/infrastructure/adapters/prompt_builder_service.dart';

/// Utilidades específicas para el proceso de onboarding
class OnboardingUtils {
  /// Genera sugerencia para "cómo nos conocimos" basada en los datos recopilados
  static Future<String> generateMeetStoryFromContext({
    required final String userName,
    required final String aiName,
    final String? userCountry,
    final String? aiCountry,
    final DateTime? userBirthdate,
  }) async {
    final prompt = PromptBuilderService.buildMeetStoryPrompt(
      userName: userName,
      aiName: aiName,
      userCountry: userCountry,
      aiCountry: aiCountry,
    );

    final profile = AiChanProfile(
      userName: userName,
      aiName: aiName,
      userBirthdate: userBirthdate ?? DateTime.now(),
      aiBirthdate: DateTime.now(),
      biography: {},
      appearance: {},
    );

    final systemPrompt = SystemPrompt(
      profile: profile,
      dateTime: DateTime.now(),
      instructions: PromptBuilderService.buildStorySystemPrompt(),
    );

    final history = [
      {
        'role': 'user',
        'content': prompt,
        'datetime': DateTime.now().toIso8601String(),
      },
    ].map((final m) => Map<String, String>.from(m)).toList();

    final response = await AIProviderManager.instance.sendMessage(
      history: history,
      systemPrompt: systemPrompt,
      capability: AICapability.textGeneration,
      preferredModel: Config.getDefaultTextModel(),
    );

    return response.text.trim();
  }
}
