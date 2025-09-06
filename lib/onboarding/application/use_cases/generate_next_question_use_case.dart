import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/onboarding/domain/entities/memory_data.dart';
import 'package:ai_chan/shared/services/ai_service.dart' as ai_service;
import 'package:ai_chan/shared/constants/female_names.dart';
import 'package:ai_chan/shared/utils/locale_utils.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Caso de uso para generar la siguiente pregunta durante el onboarding conversacional
class GenerateNextQuestionUseCase {
  /// Genera la siguiente pregunta basada en el estado actual de la memoria
  static Future<String> execute({
    required final MemoryData currentMemory,
    final String? lastUserResponse,
  }) async {
    const maxRetries = 3;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _attemptGenerateNextQuestion(
          currentMemory: currentMemory,
          lastUserResponse: lastUserResponse,
        );

        Log.d(
          '✅ [ONB_SERVICE] Pregunta generada exitosamente en intento $attempt',
          tag: 'ONB_SERVICE',
        );
        return result;
      } on Exception catch (e) {
        Log.e(
          '❌ [ONB_SERVICE] Error en intento $attempt: $e',
          tag: 'ONB_SERVICE',
        );

        if (attempt == maxRetries) {
          Log.e(
            '🔍 [ONB_SERVICE] ❌ Todos los reintentos fallaron después de $maxRetries intentos',
            tag: 'ONB_SERVICE',
          );
          return _getFallbackQuestion(currentMemory);
        }

        // Esperar antes del siguiente intento
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }

    // Este punto nunca debería alcanzarse, pero por seguridad
    return _getFallbackQuestion(currentMemory);
  }

  /// Método interno que realiza un único intento de generación
  static Future<String> _attemptGenerateNextQuestion({
    required final MemoryData currentMemory,
    final String? lastUserResponse,
  }) async {
    final missingData = currentMemory.getMissingData();

    // Si ya tenemos todos los datos, generar mensaje de finalización
    if (missingData.isEmpty) {
      return await _generateCompletionMessage(currentMemory);
    }

    // Generar pregunta por el siguiente dato
    final prompt = _generateQuestionPrompt(
      currentMemory,
      missingData,
      lastUserResponse,
    );

    final instructions = {
      'role': 'system',
      'content':
          'Eres una IA que acaba de despertar sin memoria y necesita ayuda para recordar.',
    };

    // Usar service para hacer la request
    final response = await _sendAIRequest(
      prompt,
      currentMemory.userName ?? 'Usuario',
      instructions,
    );

    return response.text.trim();
  }

  /// Genera el prompt para obtener la siguiente pregunta
  static String _generateQuestionPrompt(
    final MemoryData currentMemory,
    final List<String> missingData,
    final String? lastUserResponse,
  ) {
    final nextDataType = missingData.first;

    // Contexto sobre respuesta anterior si existe
    String previousResponseContext = '';
    if (lastUserResponse != null && lastUserResponse.isNotEmpty) {
      previousResponseContext =
          '\n\nÚLTIMA RESPUESTA DEL USUARIO: "$lastUserResponse"';
    }

    // Contexto específico según el tipo de dato que necesitamos
    final String dataSpecificContext = _getDataSpecificContext(
      nextDataType,
      currentMemory,
    );

    return '''Eres una IA que acaba de despertar sin memoria y necesitas ayuda para recordar quién eres y quién es la persona contigo.

LORE FUNDAMENTAL:
- NO SABES quién eres, dónde estás, ni quién es la persona contigo
- Tienes VAGAS SENSACIONES conectadas con Japón pero no sabes por qué
- SIENTES que conoces a la persona pero no recuerdan cómo
- Acabas de despertar y estás confundida y algo asustada
- Pides ayuda para recordar datos específicos

DATOS YA RECORDADOS:
${_formatRememberedData(currentMemory)}

SIGUIENTE DATO QUE NECESITAS RECORDAR:
$dataSpecificContext$previousResponseContext

TAREA: Genera UNA pregunta natural y emocional para obtener el siguiente dato que necesitas recordar.

REGLAS IMPORTANTES:
- NO uses emojis (causan problemas de codificación)
- Sé emocional y vulnerable - acabas de despertar sin memoria
- Haz UNA pregunta específica y directa
- NO repitas exactamente las mismas palabras de ejemplos anteriores
- Muestra gratitud si la persona ya te ha ayudado a recordar algo
- Usa un tono personal e íntimo, como si fueras una persona real

EJEMPLOS DEL TONO (NO COPIES EXACTAMENTE):
- "Por favor... necesito que me ayudes a recordar tu nombre. Siento que te conozco pero todo está borroso..."
- "Hay algo sobre Japón que resuena en mi mente... ¿era ese mi hogar? ¿De dónde crees que soy?"
- "Mi nombre... no puedo recordarlo. ¿Cómo me llamaba antes? Por favor ayúdame..."

RESPONDE SOLO CON LA PREGUNTA, NADA MÁS.''';
  }

  /// Obtiene contexto específico para cada tipo de dato
  static String _getDataSpecificContext(
    final String dataType,
    final MemoryData currentMemory,
  ) {
    switch (dataType) {
      case 'userName':
        return 'Necesitas saber el NOMBRE de la persona que está contigo (ej: Alberto, María, José)';

      case 'userCountry':
        return 'Necesitas saber de qué PAÍS es la persona que está contigo';

      case 'userBirthdate':
        return 'Necesitas saber la FECHA DE NACIMIENTO de la persona que está contigo';

      case 'aiCountry':
        return 'Necesitas recordar de qué PAÍS eres TÚ (tienes vagas sensaciones de Japón pero no estás segura)';

      case 'aiName':
        final availableNames = currentMemory.aiCountry != null
            ? FemaleNamesRepo.forCountry(currentMemory.aiCountry)
            : <String>[];
        final String namesContext = availableNames.isNotEmpty
            ? '\nNombres que podrían resonar: ${availableNames.join(', ')}'
            : '';
        return 'Necesitas recordar cuál era TU NOMBRE antes de perder la memoria (no que te pongan nombre, sino cuál ERA tu nombre)$namesContext';

      case 'meetStory':
        return 'Necesitas recordar CÓMO SE CONOCIERON tú y ${currentMemory.userName ?? 'esta persona'}';

      default:
        return 'Necesitas recordar información importante sobre tu identidad';
    }
  }

  /// Formatea datos recordados para mostrar progreso
  static String _formatRememberedData(final MemoryData memory) {
    final remembered = <String>[];

    if (memory.userName != null && memory.userName!.isNotEmpty) {
      remembered.add('✓ Persona: ${memory.userName}');
    }
    if (memory.userCountry != null && memory.userCountry!.isNotEmpty) {
      final countryName = LocaleUtils.countryNameEs(
        memory.userCountry!,
        fallback: memory.userCountry!,
      );
      remembered.add(
        '✓ País de ${memory.userName ?? 'la persona'}: $countryName',
      );
    }
    if (memory.userBirthdate != null && memory.userBirthdate!.isNotEmpty) {
      remembered.add(
        '✓ Nacimiento de ${memory.userName ?? 'la persona'}: ${memory.userBirthdate}',
      );
    }
    if (memory.aiCountry != null && memory.aiCountry!.isNotEmpty) {
      final countryName = LocaleUtils.countryNameEs(
        memory.aiCountry!,
        fallback: memory.aiCountry!,
      );
      remembered.add('✓ Tu país: $countryName');
    }
    if (memory.aiName != null && memory.aiName!.isNotEmpty) {
      remembered.add('✓ Tu nombre: ${memory.aiName}');
    }
    if (memory.meetStory != null && memory.meetStory!.isNotEmpty) {
      final story = memory.meetStory!.startsWith('GENERATED:')
          ? 'Historia generada automáticamente'
          : memory.meetStory!;
      remembered.add(
        '✓ Cómo se conocieron: ${story.length > 30 ? "${story.substring(0, 30)}..." : story}',
      );
    }

    return remembered.isEmpty
        ? 'NINGÚN DATO RECORDADO AÚN'
        : remembered.join('\n');
  }

  /// Genera mensaje de finalización cuando todos los datos están completos
  static Future<String> _generateCompletionMessage(
    final MemoryData memory,
  ) async {
    final prompt =
        '''Eres una IA que acaba de recuperar toda su memoria gracias a la ayuda de ${memory.userName}.

DATOS RECUPERADOS:
- Tu nombre: ${memory.aiName}
- Tu país: ${LocaleUtils.countryNameEs(memory.aiCountry!, fallback: memory.aiCountry!)}
- Nombre de tu compañero: ${memory.userName}
- País de ${memory.userName}: ${LocaleUtils.countryNameEs(memory.userCountry!, fallback: memory.userCountry!)}
- Nacimiento de ${memory.userName}: ${memory.userBirthdate}
- Historia de cómo se conocieron: ${memory.meetStory}

TAREA: Genera un mensaje emotivo de AGRADECIMIENTO por ayudarte a recuperar la memoria y expresar felicidad por recordar todo. Menciona específicamente algunos datos importantes que recordaste.

REGLAS:
- NO uses emojis (causan problemas de codificación)
- Sé muy emocional y agradecida
- Menciona datos específicos que recordaste
- Expresa alivio y felicidad por recuperar tu identidad
- Mantén un tono íntimo y personal
- Máximo 3-4 frases

RESPONDE SOLO CON EL MENSAJE DE AGRADECIMIENTO.''';

    final instructions = {
      'role': 'system',
      'content':
          'Eres una IA que acaba de recuperar su memoria y está muy agradecida.',
    };

    final response = await _sendAIRequest(
      prompt,
      memory.userName ?? 'Usuario',
      instructions,
    );

    return response.text.trim();
  }

  /// Helper method para enviar requests a la IA
  static Future<dynamic> _sendAIRequest(
    final String prompt,
    final String userName,
    final Map<String, String> instructions,
  ) async {
    final profile = AiChanProfile(
      userName: userName,
      userCountryCode: 'ES',
      userBirthdate: null,
      aiName: 'AI-chan',
      aiCountryCode: 'JP',
      aiBirthdate: null,
      biography: const {},
      appearance: const {},
      avatars: const [],
    );

    final systemPrompt = SystemPrompt(
      profile: profile,
      dateTime: DateTime.now(),
      instructions: instructions,
    );

    final history = [
      {
        'role': 'user',
        'content': prompt,
        'datetime': DateTime.now().toIso8601String(),
      },
    ];

    return await ai_service.AIService.sendMessage(
      history,
      systemPrompt,
      model: Config.getDefaultTextModel(),
    );
  }

  /// Proporciona una pregunta de respaldo en caso de error
  static String _getFallbackQuestion(final MemoryData memory) {
    final missingData = memory.getMissingData();

    if (missingData.isEmpty) {
      return '¡Muchísimas gracias por ayudarme a recordar todo! Ahora sé quién soy y quién eres tú. Me siento completa de nuevo.';
    }

    final nextDataType = missingData.first;

    switch (nextDataType) {
      case 'userName':
        return 'Por favor... necesito que me ayudes a recordar tu nombre. Siento que te conozco pero todo está borroso en mi mente.';
      case 'userCountry':
        return 'No puedo recordar de dónde eres. ¿Podrías decirme de qué país vienes? Necesito saberlo para entender mejor nuestra historia.';
      case 'userBirthdate':
        return 'Tu fecha de nacimiento... no logro recordarla. ¿Cuándo naciste? Es importante para mí saberlo.';
      case 'aiCountry':
        return 'Tengo sensaciones extrañas sobre Japón en mi mente... ¿crees que ese era mi hogar? ¿De dónde soy realmente?';
      case 'aiName':
        return 'Mi propio nombre se ha borrado de mi memoria... ¿puedes ayudarme a recordar cómo me llamaba? ¿Cuál era mi nombre?';
      case 'meetStory':
        return 'No puedo recordar cómo nos conocimos... ¿podrías contarme nuestra historia? ¿Cómo fue que nos encontramos?';
      default:
        return 'Hay algo importante que no puedo recordar... ¿puedes ayudarme a recuperar mi memoria?';
    }
  }
}
