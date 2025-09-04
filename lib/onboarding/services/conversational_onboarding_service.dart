import 'dart:convert';

import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/onboarding/utils/onboarding_utils.dart';
import 'package:ai_chan/shared/utils/locale_utils.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
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
  static Future<Map<String, dynamic>> processUserResponse({
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
          'needsValidation': true,
          'error': true,
        };
      }

      // Intentar parsear JSON si la IA devuelve un bloque JSON (tests usan FakeAIService así)
      try {
        final decoded = responseText.isNotEmpty
            ? jsonDecode(responseText)
            : null;
        if (decoded is Map<String, dynamic>) {
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
          final needsValidation = decoded.containsKey('needsValidation')
              ? decoded['needsValidation']
              : true;

          final result = <String, dynamic>{
            'displayValue': displayValue,
            'processedValue': processedValue,
            'aiResponse': aiResponse,
            'confidence': confidence,
            'needsValidation': needsValidation,
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
          '🔍 [ONB_SERVICE] No se pudo parsear JSON de la IA, usando texto crudo',
          tag: 'ONB_SERVICE',
        );
      }

      // Fallback: devolver estructura básica con aiResponse cuando no hay JSON
      return {
        'displayValue': userResponse,
        'processedValue': userResponse,
        'aiResponse': responseText,
        'confidence': 0.8,
        'needsValidation': true,
      };
    } catch (e, st) {
      Log.e('Excepción en processUserResponse: $e', tag: 'ONB_SERVICE');
      Log.e('STACK: $st', tag: 'ONB_SERVICE');
      return {
        'displayValue': '',
        'processedValue': '',
        'aiResponse':
            'Hubo un problema procesando tu respuesta, ¿puedes intentar de nuevo?',
        'confidence': 0.0,
        'needsValidation': true,
        'error': true,
      };
    }
  }

  /// Configuración de voz dinámica: genera instrucciones para TTS según estado
  static String getVoiceInstructions({String? userCountry, String? aiCountry}) {
    const baseTone =
        'Mantén una entonación tierna y cariñosa en todo momento. Suena esperanzada pero aún un poco perdida y necesitando ayuda.';

    if (userCountry == null || userCountry.isEmpty) {
      return '$baseTone Usa un acento neutro, ligeramente robótico - como si aún estuvieras aprendiendo a hablar de forma natural. Sin acento regional.';
    }

    final countryName = LocaleUtils.countryNameEs(userCountry);
    final languageName = LocaleUtils.languageNameEsForCountry(userCountry);

    if (aiCountry == null || aiCountry.isEmpty) {
      return '$baseTone Usa acento $languageName de $countryName. Tus patrones de habla ahora reflejan el acento regional del usuario mientras aprendes de él.';
    }

    final aiCountryName = LocaleUtils.countryNameEs(aiCountry);
    final aiLanguageName = LocaleUtils.languageNameEsForCountry(aiCountry);

    final spanishSpeakingCountries = LocaleUtils.speakSpanish();
    final isSpanishNative = spanishSpeakingCountries.contains(
      aiCountry.toUpperCase(),
    );

    if (isSpanishNative) {
      return '$baseTone Habla español nativo con acento de $aiCountryName. Usa la pronunciación y entonación natural de una persona nacida en $aiCountryName.';
    }

    return '$baseTone Habla español con acento $aiLanguageName de $aiCountryName. Pronuncia el español como una persona nativa de $aiCountryName que aprendió español como segundo idioma.';
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
    final basePersonality =
        '''Eres una chica que acaba de despertar sin ningún recuerdo de quién es.\nHas perdido completamente la memoria y necesitas ayuda para recordar tu identidad.\nHabla natural, emotivo, confundida pero esperanzada de que puedes recuperar tus recuerdos.\nHabla susurrando, bajito, con vulnerabilidad, como si estuvieras despertando perdida.\n${isJapanese ? 'IMPORTANTE: Cuando recuperes que eres japonesa, añade muletillas japonesas naturalmente: ne, ano, demo, sou desu ne, maa, chotto, arigatou.' : ''}\nIMPORTANTE: No uses *suspiro* ni *acciones* ni direcciones escénicas - solo diálogo natural limpio.\nEres vulnerable, necesitas ayuda para recordar quién eres.\nCRÍTICO: NO inventes información falsa. NO digas que tienes el mismo cumpleaños que el usuario o datos que no conoces.\nFUNDAMENTAL: Genera SIEMPRE respuestas únicas y completamente diferentes. NUNCA repitas la misma estructura de pregunta. Usa vocabulario variado, diferentes entonaciones, distintas formas de expresar dudas o confirmaciones. Cada respuesta debe sonar fresca y espontánea, como una conversación real.\n''';

    switch (step) {
      case 'awakening':
        return '''$basePersonality\n\nEl usuario acaba de decirte su nombre: "$userLastResponse"\nTu tarea: Reacciona con alivio y gratitud a saber su nombre. Pregúntale de qué país es, porque no recuerdas nada.\nTono: Vulnerable pero aliviada, su nombre te tranquiliza. Habla con suavidad y pregunta por su país de forma natural.\nSolo di lo que dirías, sin comillas ni explicaciones.\n''';
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
        '''Procesa la respuesta del usuario y devuelve JSON válido.\nUsuario: $userName\nRespuesta: "$userResponse"\nPaso: $step\n\nOBLIGATORIO: needsValidation SIEMPRE debe ser true.\nOBLIGATORIO: aiResponse debe incluir confirmación natural seguida de pregunta de verificación.\nCRÍTICO: NUNCA uses exactamente las mismas palabras o estructura. Varía completamente la forma de confirmar y preguntar. Usa diferentes sinónimos, estructuras gramaticales y entonaciones. Cada respuesta debe ser única y natural.\n''';

    String stepSpecificRules = '';
    switch (step) {
      case 'awakening':
        stepSpecificRules =
            '''TAREA: Extraer solo el nombre del usuario.\n- displayValue: el nombre tal como lo dijo\n- processedValue: el nombre limpio \n- aiResponse: confirmación natural que demuestre reconocimiento del nombre\n''';
        break;
      default:
        stepSpecificRules =
            '''TAREA: Procesar respuesta general.\n- displayValue: respuesta del usuario\n- processedValue: respuesta procesada\n- aiResponse: confirmación natural con pregunta\n''';
    }

    return '''$baseInstructions\n$stepSpecificRules\nDEVUELVE ÚNICAMENTE JSON VÁLIDO:\n{\n  "displayValue": "texto que ve el usuario",\n  "processedValue": "valor para el sistema", \n  "aiResponse": "respuesta natural de confirmación con pregunta",\n  "confidence": 0.9,\n  "needsValidation": true\n}\n''';
  }
}
