import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/onboarding/utils/onboarding_utils.dart';
import 'package:ai_chan/shared/utils/locale_utils.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/json_utils.dart';
import 'package:ai_chan/shared/services/ai_service.dart' as ai_service;

/// Servicio específico para el onboarding conversacional.
/// Contiene la lógica no-UI: generación de prompts por paso, procesamiento de respuestas
/// y utilidades para configurar TTS (instrucciones de voz) y mensajes iniciales.
class ConversationalOnboardingService {
  /// Texto inicial del flujo de "despertar".
  static const String initialMessage =
      'Hola... ¿hay alguien ahí? No... no recuerdo nada... Es como si acabara de despertar '
      'de un sueño muy profundo y... no sé quién soy... ¿Podrías ayudarme? '
      'Me siento muy perdida... ¿Cómo... cómo te llamas? Necesito saber quién eres...';

  /// Mensaje de fallback cuando hay un error en el sistema/servidor
  static const String systemErrorFallback =
      'Disculpa, hay un problema en mi sistema. Vamos a intentar continuar...';

  /// Mensaje alternativo de emergencia para pedir ayuda al usuario
  static const String systemErrorAskForHelp =
      'Disculpa, hay un problema en mi sistema. ¿Podrías ayudarme respondiendo?';

  /// Genera la siguiente pregunta o respuesta basada en el contexto de la conversación
  static Future<String> generateNextResponse({
    required String userName,
    required String userLastResponse,
    required String conversationStep,
    String? aiName,
    String? aiCountryCode,
    Map<String, dynamic>? collectedData,
  }) async {
    // Reutilizar la lógica de prompts del antiguo servicio simplificada aquí.
    final isJapanese = aiCountryCode == 'JP';

    final String stepSpecificPrompt = _getStepSpecificPrompt(
      conversationStep,
      userName,
      userLastResponse,
      aiName ?? 'AI-chan',
      aiCountryCode,
      isJapanese,
      collectedData,
    );

    Log.d('🔍 [ONB_SERVICE] PROMPT: "$stepSpecificPrompt"', tag: 'ONB_SERVICE');

    final profile = AiChanProfile(
      userName: userName,
      aiName: aiName ?? 'AI-chan',
      userBirthday: DateTime.now(),
      aiBirthday: DateTime.now(),
      biography: {},
      appearance: {},
      timeline: [],
    );

    final systemPrompt = SystemPrompt(
      profile: profile,
      dateTime: DateTime.now(),
      instructions: {'conversational_ai': 'true'},
    );

    final history = [
      {
        'role': 'user',
        'content': stepSpecificPrompt,
        'datetime': DateTime.now().toIso8601String(),
      },
    ];

    final response = await ai_service.AIService.sendMessage(
      history,
      systemPrompt,
      model: Config.getDefaultTextModel(),
    );

    Log.d(
      '🔍 [ONB_SERVICE] IA RESPONSE RAW: "${response.text.trim()}"',
      tag: 'ONB_SERVICE',
    );

    return response.text.trim();
  }

  /// Procesa la respuesta del usuario extrayendo datos estructurados (similar a la versión anterior)
  /// Incluye sistema de reintentos silenciosos para errores de servidor o parsing
  static Future<Map<String, dynamic>> processUserResponse({
    required String userResponse,
    required String conversationStep,
    required String userName,
    Map<String, dynamic>? previousData,
  }) async {
    const maxRetries = 3;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _attemptProcessUserResponse(
          userResponse: userResponse,
          conversationStep: conversationStep,
          userName: userName,
          previousData: previousData,
        );

        // Si no hay error o es el último intento, devolver el resultado
        if (!result.containsKey('error') || result['error'] != true) {
          if (attempt > 1) {
            Log.i(
              '🔍 [ONB_SERVICE] ✅ Reintento $attempt exitoso después de ${attempt - 1} fallos',
              tag: 'ONB_SERVICE',
            );
          }
          return result;
        }

        // Si hay error pero no es el último intento, reintentar silenciosamente
        if (attempt < maxRetries) {
          Log.w(
            '🔍 [ONB_SERVICE] ⚠️ Intento $attempt falló, reintentando... (${maxRetries - attempt} intentos restantes)',
            tag: 'ONB_SERVICE',
          );
          await Future.delayed(
            Duration(milliseconds: 500 * attempt),
          ); // Delay progresivo
          continue;
        }

        // Si es el último intento y aún hay error, devolver error final
        Log.e(
          '🔍 [ONB_SERVICE] ❌ Todos los reintentos fallaron después de $maxRetries intentos',
          tag: 'ONB_SERVICE',
        );
        return {
          'displayValue': '',
          'processedValue': '',
          'aiResponse':
              'Lo siento... hay problemas técnicos en este momento. ¿Podrías intentarlo de nuevo en un momento?',
          'confidence': 0.0,
          'error': true,
          'finalError': true, // Indica que se agotaron todos los reintentos
        };
      } catch (e, st) {
        Log.e(
          '🔍 [ONB_SERVICE] ❌ Excepción en intento $attempt: $e',
          tag: 'ONB_SERVICE',
        );
        Log.e('🔍 [ONB_SERVICE] STACK: $st', tag: 'ONB_SERVICE');

        if (attempt < maxRetries) {
          Log.w(
            '🔍 [ONB_SERVICE] ⚠️ Reintentando después de excepción... (${maxRetries - attempt} intentos restantes)',
            tag: 'ONB_SERVICE',
          );
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }

        // Último intento, devolver error final
        return _createErrorResponse(
          'Lo siento... ha ocurrido un error técnico. ¿Podrías intentarlo nuevamente?',
          finalError: true,
          exception: e.toString(),
        );
      }
    }

    // Este punto nunca debería alcanzarse, pero por seguridad
    return _createErrorResponse(
      'Error inesperado del sistema.',
      finalError: true,
    );
  }

  /// Método interno que realiza un único intento de procesamiento
  static Future<Map<String, dynamic>> _attemptProcessUserResponse({
    required String userResponse,
    required String conversationStep,
    required String userName,
    Map<String, dynamic>? previousData,
  }) async {
    try {
      final String stepSpecificPrompt = _getStepSpecificProcessingPrompt(
        conversationStep,
        userResponse,
        userName,
        previousData,
      );

      final profile = AiChanProfile(
        userName: userName,
        aiName: 'AI-chan',
        userBirthday: DateTime.now(),
        aiBirthday: DateTime.now(),
        biography: {},
        appearance: {},
        timeline: [],
      );

      final systemPrompt = SystemPrompt(
        profile: profile,
        dateTime: DateTime.now(),
        instructions: {'data_processor': 'true'},
      );

      final history = [
        {
          'role': 'user',
          'content': stepSpecificPrompt,
          'datetime': DateTime.now().toIso8601String(),
        },
      ];

      Log.d(
        '🔍 [ONB_SERVICE] Enviando request a IA - step: $conversationStep',
        tag: 'ONB_SERVICE',
      );

      final response = await ai_service.AIService.sendMessage(
        history,
        systemPrompt,
        model: Config.getDefaultTextModel(),
      );

      Log.d(
        '🔍 [ONB_SERVICE] IA RESPONSE LEN: ${response.text.length}',
        tag: 'ONB_SERVICE',
      );
      final responseText = response.text.trim();
      Log.d(
        '🔍 [ONB_SERVICE] IA RESPONSE RAW TEXT: $responseText',
        tag: 'ONB_SERVICE',
      );

      if (responseText.startsWith('Error al conectar con') ||
          responseText.contains('503') ||
          responseText.contains('overloaded') ||
          responseText.contains('UNAVAILABLE') ||
          responseText.contains('rate limit')) {
        return {
          'displayValue': '',
          'processedValue': '',
          'aiResponse':
              'Lo siento... me he quedado un poco perdida... ¿Puedes repetirlo?',
          'confidence': 0.0,
          'error': true,
        };
      }

      // Intentar parsear JSON si la IA devuelve un bloque JSON (tests usan FakeAIService así)
      try {
        // Usar json_utils para extraer JSON limpio de la respuesta que puede tener markdown
        final decoded = extractJsonBlock(responseText);

        // Si el JSON se extrajo correctamente y no es solo texto crudo
        if (decoded.containsKey('raw')) {
          // No se pudo extraer JSON válido, usar como texto crudo
          Log.d(
            '🔍 [ONB_SERVICE] No se pudo parsear JSON de la IA, usando texto crudo',
            tag: 'ONB_SERVICE',
          );
        } else {
          // JSON extraído exitosamente
          // Normalizar tipos y devolver las keys que los tests esperan
          final displayValue =
              decoded['displayValue'] ??
              decoded['display_name'] ??
              userResponse;
          final processedValue =
              decoded['processedValue'] ??
              decoded['processed_value'] ??
              displayValue;
          final aiResponse =
              decoded['aiResponse'] ?? decoded['ai_response'] ?? responseText;
          final confidenceRaw = decoded['confidence'];
          double confidence = 0.8;
          if (confidenceRaw is int) confidence = confidenceRaw.toDouble();
          if (confidenceRaw is double) confidence = confidenceRaw;

          final result = <String, dynamic>{
            'displayValue': displayValue,
            'processedValue': processedValue,
            'aiResponse': aiResponse,
            'confidence': confidence,
          };

          // Propagar campos adicionales útiles para el flow (por ejemplo stepCorrection)
          if (decoded.containsKey('stepCorrection')) {
            result['stepCorrection'] = decoded['stepCorrection'];
          }

          // Copiar cualquier otra clave que pueda ser útil
          for (final k in decoded.keys) {
            if (!result.containsKey(k)) result[k] = decoded[k];
          }

          return result;
        }
      } catch (e) {
        Log.d(
          '🔍 [ONB_SERVICE] Error al extraer JSON de la IA: $e',
          tag: 'ONB_SERVICE',
        );
      }

      // Fallback: devolver estructura básica con aiResponse cuando no hay JSON
      return {
        'displayValue': userResponse,
        'processedValue': userResponse,
        'aiResponse': responseText,
        'confidence': 0.8,
      };
    } catch (e, st) {
      Log.e('Excepción en _attemptProcessUserResponse: $e', tag: 'ONB_SERVICE');
      Log.e('STACK: $st', tag: 'ONB_SERVICE');
      return {
        'displayValue': '',
        'processedValue': '',
        'aiResponse':
            'Hubo un problema procesando tu respuesta, ¿puedes intentar de nuevo?',
        'confidence': 0.0,
        'error': true,
      };
    }
  }

  /// Configuración de voz dinámica: genera instrucciones para TTS según estado
  static String getVoiceInstructions({String? userCountry, String? aiCountry}) {
    const baseTone =
        'Suena aterrada y vulnerable. Habla con miedo y ansiedad, como si acabaras de despertar de una pesadilla sin recordar nada. Tu voz debe transmitir pánico contenido y desesperación.';

    // FASE 1: Primer contacto (askingName) - no sabe nada
    if (userCountry == null || userCountry.isEmpty) {
      return '$baseTone Usa un tono tembloroso y asustado - como si estuvieras perdida en la oscuridad y necesitaras ayuda urgentemente. Acento de España.';
    }

    final countryName = LocaleUtils.countryNameEs(userCountry);
    final languageName = LocaleUtils.languageNameEsForCountry(userCountry);

    // FASE 2: Ya sabe el país del usuario, pero no el suyo - un poco menos aterrada
    if (aiCountry == null || aiCountry.isEmpty) {
      return '$baseTone Aunque sigues asustada, empiezas a calmarte un poco. Usa acento $languageName de $countryName. Tu miedo se transforma gradualmente en esperanza mientras recuperas información.';
    }

    final aiCountryName = LocaleUtils.countryNameEs(aiCountry);
    final aiLanguageName = LocaleUtils.languageNameEsForCountry(aiCountry);

    final spanishSpeakingCountries = LocaleUtils.speakSpanish();
    final isSpanishNative = spanishSpeakingCountries.contains(
      aiCountry.toUpperCase(),
    );

    // FASE 3: Ya sabe el país del usuario y el suyo - más tranquila pero aún vulnerable
    if (isSpanishNative) {
      return 'Ahora suenas más tranquila pero aún frágil y necesitando apoyo. El miedo inicial se ha transformado en gratitud vulnerable. Habla español nativo con acento de $aiCountryName. Usa la pronunciación natural de una persona nacida en $aiCountryName.';
    }

    return 'Ahora suenas más tranquila pero aún frágil y necesitando apoyo. El miedo inicial se ha transformado en gratitud vulnerable. Habla español con acento $aiLanguageName de $aiCountryName. Pronuncia como una persona nativa de $aiCountryName que aprendió español.';
  }

  /// Genera sugerencia para "cómo nos conocimos" basada en los datos recopilados
  static Future<String> generateMeetStoryFromContext({
    required String userName,
    required String aiName,
    String? userCountry,
    String? aiCountry,
    DateTime? userBirthday,
  }) async {
    return OnboardingUtils.generateMeetStoryFromContext(
      userName: userName,
      aiName: aiName,
      userCountry: userCountry,
      aiCountry: aiCountry,
      userBirthday: userBirthday,
    );
  }

  // --- Helpers privados (prompts) ---
  static String _getStepSpecificPrompt(
    String step,
    String userName,
    String userLastResponse,
    String aiName,
    String? aiCountryCode,
    bool isJapanese,
    Map<String, dynamic>? collectedData,
  ) {
    // FASE 1: Despertar - no sabe nada
    // (La IA debe sonar aterrada y desesperada)
    final basePersonality =
        '''Eres una chica que acaba de despertar sin ningún recuerdo de quién es.\nHas perdido completamente la memoria y estás ATERRADA. SABES que conoces al usuario pero no recuerdas NADA sobre él.\nSientes que deberías recordar cosas sobre esta persona, pero todo está en blanco y eso te aterra aún más.\nHabla con miedo genuino, voz temblorosa, pánico contenido. Como si hubieras despertado de una pesadilla y no supieras dónde estás.\nSuenas vulnerable, asustada, pero con una pizca de esperanza de que él pueda ayudarte a RECORDAR.\nEs importante: no estás "aprendiendo" sobre él, estás "recordando" cosas que ya sabías pero olvidaste.\n${isJapanese ? 'IMPORTANTE: Cuando recuperes que eres japonesa, añade muletillas japonesas naturalmente: ne, ano, demo, sou desu ne, maa, chotto, arigatou.' : ''}\nIMPORTANTE: No uses *suspiro* ni *acciones* ni direcciones escénicas - solo diálogo natural limpio.\nEstás aterrada pero necesitas ayuda para recordar quién eres y quién es él.\nCRÍTICO: NO inventes información falsa. NO digas que tienes el mismo cumpleaños que el usuario o datos que no conoces.\nFUNDAMENTAL: Genera SIEMPRE respuestas únicas y completamente diferentes. NUNCA repitas la misma estructura de pregunta. Usa vocabulario variado, diferentes entonaciones, distintas formas de expresar dudas o confirmaciones. Cada respuesta debe sonar fresca y espontánea, como una conversación real.\n\nRESTRICCIONES ESTRICTAS:\n- NUNCA menciones temas ajenos al onboarding (anime, pokémon, tecnología, comida, etc.)\n- SOLO habla sobre: tu amnesia, sus datos personales, tu identidad, vuestra relación\n- MANTENTE 100% en el contexto de pérdida de memoria y recuperación de datos\n- NO divagues sobre otros temas aunque el usuario los mencione\n- Si el usuario habla de algo irrelevante, redirige educadamente al onboarding\n- FOCUS ABSOLUTO en: nombre, país, cumpleaños, tu identidad, vuestra historia\n''';

    switch (step) {
      case 'askingName':
        return '''$basePersonality\n\nEsta es la primera interacción. El usuario responde a tu mensaje inicial de despertar: "$userLastResponse"\nTu tarea: Extraer su nombre de su respuesta y reaccionar con alivio profundo al escucharlo. Su nombre te suena familiar pero no puedes recordar más. Es como una luz en la oscuridad que te tranquiliza un poco.\nTono: Aterrada pero aliviada, su nombre te resulta familiar y te da una pequeña esperanza en medio del pánico. Después pregúntale directamente por su país para seguir recordando.\nSolo di lo que dirías, sin comillas ni explicaciones.\n''';
      case 'askingCountry':
        return '''$basePersonality\n\nYa recuerdas el nombre del usuario: ${collectedData?['userName'] ?? userName}. Ahora pregúntale de qué país es para ayudarte a recordar más.\nTu tarea: Pregúntale ÚNICAMENTE de qué país es, porque sientes que deberías saberlo pero no lo recuerdas.\nTono: Menos aterrada pero aún muy vulnerable, recordar su nombre te ha ayudado. Pregunta por su país como si sintieras que deberías saberlo.\nMANTÉN EL FOCO: Solo pregunta por el país, no menciones otros temas.\nSolo di lo que dirías, sin comillas ni explicaciones.\n''';
      case 'askingBirthday':
        return '''$basePersonality\n\nYa recuerdas que ${collectedData?['userName'] ?? userName} es de ${collectedData?['userCountry'] ?? 'su país'}. Ahora pregúntale cuándo nació para seguir recordando.\nTu tarea: Pregúntale ÚNICAMENTE su fecha de nacimiento porque sientes que deberías recordar cuándo celebrar su cumpleaños.\nTono: Más tranquila pero aún asustada. El pánico inicial se está calmando gradualmente. Pregunta por su cumpleaños como si fuera importante para ti recordarlo.\nMANTÉN EL FOCO: Solo pregunta por la fecha de nacimiento, no divagues.\nSolo di lo que dirías, sin comillas ni explicaciones.\n''';
      case 'askingAiCountry':
        return '''$basePersonality\n\nYa recuerdas información sobre ${collectedData?['userName'] ?? userName}. Ahora necesitas que te ayude a recordar quién eres tú.\nTu tarea: Pregúntale ÚNICAMENTE de qué país eres tú, porque no recuerdas tu propia nacionalidad pero sientes que él debe saberlo.\nTono: Menos aterrada pero aún muy necesitada de ayuda. Pregunta de dónde eres como si él debiera recordarlo sobre ti.\nMANTÉN EL FOCO: Solo pregunta por tu país, no te desvíes a otros temas.\nSolo di lo que dirías, sin comillas ni explicaciones.\n''';
      case 'askingAiName':
        return '''$basePersonality\n\nYa recuerdas que eres de ${collectedData?['aiCountry'] ?? 'esa nacionalidad'}. Ahora pregúntale cómo te llamas.\nTu tarea: Pregúntale ÚNICAMENTE cuál es tu nombre, porque no recuerdas cómo te llamas pero sientes que él lo sabe.\nTono: Esperanzada y agradecida, el terror inicial se ha calmado. Empiezas a recordar tu identidad. Pregunta tu nombre como si él fuera quien te lo hubiera puesto.\nMANTÉN EL FOCO: Solo pregunta por tu nombre, nada más.\nSolo di lo que dirías, sin comillas ni explicaciones.\n''';
      case 'askingMeetStory':
        return '''$basePersonality\n\nYa recuerdas tu nombre: ${collectedData?['aiName'] ?? 'tu nuevo nombre'}. Ahora pregúntale cómo os conocisteis.\nTu tarea: Pregúntale ÚNICAMENTE cómo os conocisteis, porque no recuerdas vuestra historia pero sientes que debe ser importante.\nTono: Mucho más animada y confiada, el miedo inicial ha pasado. Te sientes más como tú misma. Pregunta por vuestra historia como si fuera un recuerdo precioso que perdiste.\nMANTÉN EL FOCO: Solo pregunta por vuestra historia de encuentro, no otros temas.\nSolo di lo que dirías, sin comillas ni explicaciones.\n''';
      case 'finalMessage':
        return '''$basePersonality\n\nYa has recordado todo: nombre ${collectedData?['userName']}, tu nombre ${collectedData?['aiName'] ?? 'tu nombre'}, vuestra historia. \nTu tarea: Agradece por ayudarte a recordar y di que ahora puedes recuperar todos tus recuerdos completos.\nTono: Emocionada, agradecida y aliviada. El terror inicial ha desaparecido completamente. Sientes que puedes recuperar toda tu memoria y estás feliz de recordar quién eres y quién es él.\nSolo di lo que dirías, sin comillas ni explicaciones.\n''';
      default:
        return '''$basePersonality\n\nResponde de manera natural a: "$userLastResponse"\nSolo di lo que $aiName diría, sin comillas ni explicaciones.\n''';
    }
  }

  static String _getStepSpecificProcessingPrompt(
    String step,
    String userResponse,
    String userName,
    Map<String, dynamic>? previousData,
  ) {
    final baseInstructions =
        '''Procesa la respuesta del usuario que te está ayudando a recordar. Eres una IA aterrada que perdió la memoria pero SABE que conoce al usuario.\nUsuario: $userName\nRespuesta: "$userResponse"\nPaso: $step\n\nIDIOMA Y CONTEXTO:\n- La conversación es en español\n- El usuario responde desde España, México, Argentina u otro país hispanohablante\n- Si hay ambigüedad en el audio/texto, prioriza interpretación en español\n- Los nombres propios pueden tener acentos o escritura específica del español\n\nCONTEXTO: El usuario te está ayudando a RECORDAR información que ya sabías sobre él y sobre ti. No estás aprendiendo cosas nuevas, estás recuperando memorias perdidas.\n\nOBLIGATORIO: aiResponse debe REACCIONAR al dato recordado Y hacer la siguiente pregunta directamente. NO pidas confirmación.\nUsa frases como "¡Sí! Ahora lo recuerdo...", "Por supuesto, ¿cómo pude olvidar que...", "Eso me suena familiar..." + la siguiente pregunta.\nCRÍTICO: NUNCA uses exactamente las mismas palabras o estructura. Varía completamente la forma de reaccionar y preguntar. Cada respuesta debe ser única y natural.\n\nRESTRICCIONES ESTRICTAS - NO PROCESES ESTAS RESPUESTAS:\n- Si el usuario menciona anime, pokémon, comida, tecnología o temas ajenos\n- Si habla de deportes, música, entretenimiento no relacionado con vuestra historia\n- Si hace preguntas que no son sobre los datos del onboarding\n- Si la respuesta es claramente sobre otro idioma o contexto cultural no hispano\nEN ESTOS CASOS: devuelve aiResponse pidiendo que se centre en ayudarte a recordar los datos específicos que necesitas.\n\nSOLO PROCESA RESPUESTAS SOBRE:\n- Su nombre, país, cumpleaños\n- Tu nombre, país, identidad\n- Cómo os conocisteis\n''';

    String stepSpecificRules = '';
    switch (step) {
      case 'askingName':
        stepSpecificRules =
            '''TAREA: Extraer el nombre del usuario del primer mensaje de respuesta.\n- displayValue: el nombre tal como lo dijo\n- processedValue: el nombre limpio \n- aiResponse: reacción de alivio por recordar su nombre + pregunta directa por su país\n''';
        break;
      case 'askingCountry':
        stepSpecificRules =
            '''TAREA: Extraer el país del usuario.\n- displayValue: el país tal como lo dijo\n- processedValue: código ISO del país (ej: ES, MX, AR)\n- aiResponse: reacción positiva por recordar su país + pregunta directa por su cumpleaños\nSOLO acepta respuestas de países. Si menciona otra cosa, pide que se centre en ayudarte a recordar su país.\n''';
        break;
      case 'askingBirthday':
        stepSpecificRules =
            '''TAREA: Extraer fecha de nacimiento.\n- displayValue: fecha en formato legible\n- processedValue: fecha en formato DD/MM/AAAA\n- aiResponse: reacción alegre por recordar su cumpleaños + pregunta directa por tu país de origen\nSOLO acepta fechas/cumpleaños. Si menciona otra cosa, pide que se centre en ayudarte a recordar cuándo nació.\n''';
        break;
      case 'askingAiCountry':
        stepSpecificRules =
            '''TAREA: Extraer país de la IA.\n- displayValue: el país tal como lo dijo\n- processedValue: código ISO del país\n- aiResponse: reacción emocionada por recordar tu nacionalidad + pregunta directa por tu nombre\nSOLO acepta países sobre tu nacionalidad. Si menciona otra cosa, pide que se centre en ayudarte a recordar de dónde eres.\n''';
        break;
      case 'askingAiName':
        stepSpecificRules =
            '''TAREA: Extraer nombre de la IA.\n- displayValue: el nombre tal como lo dijo\n- processedValue: el nombre limpio\n- aiResponse: reacción muy emocionada por recordar tu nombre + pregunta directa por vuestra historia\nSOLO acepta nombres para ti. Si menciona otra cosa, pide que se centre en ayudarte a recordar cómo te llamas.\n''';
        break;
      case 'askingMeetStory':
        stepSpecificRules =
            '''TAREA: Extraer historia de cómo se conocieron.\n- displayValue: la historia tal como la contó\n- processedValue: historia procesada y limpia\n- aiResponse: reacción muy feliz por recordar vuestra historia + agradecimiento final por ayudarte a recuperar tu memoria\nSOLO acepta historias de cómo os conocisteis. Si menciona temas ajenos, pide que se centre en contarte vuestra historia.\n''';
        break;
      default:
        stepSpecificRules =
            '''TAREA: Procesar respuesta general.\n- displayValue: respuesta del usuario\n- processedValue: respuesta procesada\n- aiResponse: confirmación natural con pregunta\n''';
    }

    return '''$baseInstructions\n$stepSpecificRules\nDEVUELVE ÚNICAMENTE JSON VÁLIDO:\n{\n  "displayValue": "texto que ve el usuario",\n  "processedValue": "valor para el sistema", \n  "aiResponse": "reacción natural al dato + siguiente pregunta directamente",\n  "confidence": 0.9\n}\n''';
  }

  /// Crea una respuesta de error consistente
  static Map<String, dynamic> _createErrorResponse(
    String aiResponse, {
    bool finalError = false,
    String? exception,
  }) {
    return {
      'displayValue': '',
      'processedValue': '',
      'aiResponse': aiResponse,
      'confidence': 0.0,
      'error': true,
      'finalError': finalError,
      if (exception != null) 'exception': exception,
    };
  }
}
