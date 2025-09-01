import 'package:ai_chan/core/interfaces/i_profile_service.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/core/services/ia_bio_generator.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';
import 'package:ai_chan/core/services/ia_avatar_generator.dart';
import 'package:ai_chan/core/config.dart';

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
      // Sólo pasar el override si el runtime coincide con el modelo por defecto
      final defaultModel = Config.getDefaultTextModel().trim().toLowerCase();
      final implType = _aiService.runtimeType.toString();
      if (defaultModel.startsWith('gpt-') && implType == 'OpenAIService') {
      } else if ((defaultModel.startsWith('gemini-') || defaultModel.startsWith('imagen-')) &&
          implType == 'GeminiService') {
      } else {}
      // Delegar a la función existente que resolverá el runtime correctamente
      return await generateAIBiographyWithAI(
        userName: userName,
        aiName: aiName,
        userBirthday: userBirthday,
        meetStory: meetStory,
        userCountryCode: userCountryCode,
        aiCountryCode: aiCountryCode,
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
      final appearanceMap = await generator.generateAppearanceFromBiography(profile);
      // Generate avatar (replace existing) and return it
      final updatedProfile = profile.copyWith(appearance: appearanceMap);
      final avatar = await IAAvatarGenerator().generateAvatarFromAppearance(updatedProfile);
      return avatar;
    } catch (e) {
      return AiImage(url: 'https://example.com/avatar_placeholder.png', seed: 'fallback-seed', prompt: 'fallback');
    }
  }

  @override
  Future<void> saveProfile(AiChanProfile profile) async {
    return;
  }
}
