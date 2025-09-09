import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_manager.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/infrastructure/adapters/prompt_builder_service.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Generador de historias de encuentro personalizado para AI-chan
/// Maneja la creación de historias coherentes de cómo se conocieron el usuario y la IA
class IAMeetStoryGenerator {
  /// Máximo número de reintentos para generar historia válida
  static const int maxAttempts = 3;

  /// Genera historia de encuentro basada en el contexto proporcionado
  Future<String> generateMeetStoryFromContext({
    required final String userName,
    required final String aiName,
    final String? userCountry,
    final String? aiCountry,
    final DateTime? userBirthdate,
  }) async {
    if (userName.trim().isEmpty || aiName.trim().isEmpty) {
      throw ArgumentError(
        'userName y aiName son requeridos para generar meetstory',
      );
    }

    String? storyText;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
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

        final generatedText = response.text.trim();

        if (_isValidMeetStory(generatedText)) {
          storyText = generatedText;
          Log.d(
            '[IAMeetStoryGenerator] Historia válida generada en intento ${attempt + 1}',
          );
          break;
        }

        Log.w(
          '[IAMeetStoryGenerator] Historia inválida en intento ${attempt + 1}, reintentando...',
        );
      } on Exception catch (err) {
        Log.e('[IAMeetStoryGenerator] Error en intento ${attempt + 1}: $err');
      }

      // Backoff incremental entre reintentos (excepto en el último intento)
      if (attempt < maxAttempts - 1) {
        await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }

    if (storyText == null) {
      throw Exception(
        'No se pudo generar historia de encuentro válida después de $maxAttempts intentos',
      );
    }

    return storyText;
  }

  /// Valida que la historia generada tenga contenido apropiado
  bool _isValidMeetStory(final String story) {
    if (story.isEmpty) return false;

    // Debe tener al menos 20 caracteres para ser una historia mínimamente descriptiva
    if (story.length < 20) return false;

    // No debe contener marcadores de error comunes
    final lowercaseStory = story.toLowerCase();
    if (lowercaseStory.contains('error') ||
        lowercaseStory.contains('failed') ||
        lowercaseStory.contains('unable') ||
        lowercaseStory.contains('cannot generate')) {
      return false;
    }

    // Debe parecer una narrativa coherente (contiene algunas palabras clave)
    final hasStoryElements =
        lowercaseStory.contains('conocim') ||
        lowercaseStory.contains('encontr') ||
        lowercaseStory.contains('conocer') ||
        lowercaseStory.contains('primera vez') ||
        lowercaseStory.contains('cuando') ||
        lowercaseStory.contains('donde') ||
        lowercaseStory.contains('cómo');

    return hasStoryElements;
  }
}
