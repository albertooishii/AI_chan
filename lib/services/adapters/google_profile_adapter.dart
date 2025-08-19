import 'package:ai_chan/core/interfaces/i_profile_service.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/services/ai_service.dart';
import 'package:ai_chan/core/services/ia_bio_generator.dart';
import 'package:ai_chan/core/services/ia_appearance_generator.dart';

/// Google/Gemini adapter real: delega la generación de biografía y apariencia
/// a los generadores existentes pasando una instancia de [GeminiService].
///
/// Permite inyectar una implementación de [AIService] para tests.
class GoogleProfileAdapter implements IProfileService {
  final AIService _aiService;

  /// Constructor que requiere la inyección de una implementación de `AIService`.
  GoogleProfileAdapter({required AIService aiService}) : _aiService = aiService;

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
      // Si falla por falta de claves o inicialización (tests/local), caer en un fallback determinista.
      // Esto permite que la app siga funcionando sin claves en entorno local, pero cuando las claves
      // estén presentes se usará GeminiService.
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
      // Fallback a imagen placeholder cuando la generación falla por falta de servicio
      return AiImage(url: 'https://example.com/avatar_placeholder.png', seed: 'fallback-seed', prompt: 'fallback');
    }
  }

  @override
  Future<void> saveProfile(AiChanProfile profile) async {
    // Actualmente la persistencia global la maneja repositorios/StorageUtils.
    // Aquí dejamos un no-op para mantener la interfaz; si se requiere,
    // podemos inyectar un IStorageService y guardar el perfil.
    return;
  }
}
