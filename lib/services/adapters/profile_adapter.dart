import 'package:ai_chan/core/interfaces/i_profile_service.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/services/ai_service.dart';
import 'package:ai_chan/core/services/ia_bio_generator.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';

/// Adaptador canónico de perfil: delega la generación de biografía y apariencia
/// a los generadores existentes pasando una instancia de [AIService].
///
/// Permite inyectar una implementación de [AIService] para tests.
class ProfileAdapter implements IProfileService {
  final AIService _aiService;

  /// Constructor que requiere la inyección de una implementación de `AIService`.
  ProfileAdapter({required AIService aiService}) : _aiService = aiService;

  @override
  Future<AiChanProfile> generateBiography({
    required String userName,
    required String aiName,
    required DateTime userBirthday,
    required String meetStory,
    String? userCountryCode,
    String? aiCountryCode,
  }) async {
    try {
      // Delegar a la función existente que soporta inyección de AIService
      return await generateAIBiographyWithAI(
        userName: userName,
        aiName: aiName,
        userBirthday: userBirthday,
        meetStory: meetStory,
        userCountryCode: userCountryCode,
        aiCountryCode: aiCountryCode,
        aiServiceOverride: _aiService,
      );
    } catch (e) {
      // Fallback determinista para entornos sin claves
      return AiChanProfile(
        userName: userName,
        aiName: aiName,
        userBirthday: userBirthday,
        aiBirthday: DateTime.now(),
        biography: {
          'summary': 'Generated fallback biography for $aiName due to unavailable remote service.',
          'note': e.toString(),
        },
        appearance: {'style': 'fallback'},
        timeline: [],
      );
    }
  }

  @override
  Future<AiImage?> generateAppearance(AiChanProfile profile) async {
    try {
      final generator = IAAppearanceGenerator();
      final result = await generator.generateAppearancePromptWithImage(
        profile,
        aiService: _aiService,
      );
      return result['avatar'] as AiImage?;
    } catch (e) {
      return AiImage(url: 'https://example.com/avatar_placeholder.png', seed: 'fallback-seed', prompt: 'fallback');
    }
  }

  @override
  Future<void> saveProfile(AiChanProfile profile) async {
    return;
  }
}
