import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/onboarding/utils/onboarding_utils.dart';
import 'package:ai_chan/shared/utils/locale_utils.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/json_utils.dart';
import 'package:ai_chan/shared/services/ai_service.dart' as ai_service;
import 'package:ai_chan/shared/constants/female_names.dart';

/// Datos que la IA necesita recuperar durante el onboarding
class MemoryData {
  String? userName;
  String? userCountry;
  String? userBirthdate;
  String? aiCountry;
  String? aiName;
  String? meetStory;

  MemoryData({
    this.userName,
    this.userCountry,
    this.userBirthdate,
    this.aiCountry,
    this.aiName,
    this.meetStory,
  });

  /// Obtiene lista de datos que aún faltan por recuperar
  List<String> getMissingData() {
    final missing = <String>[];
    if (userName == null || userName!.trim().isEmpty) missing.add('userName');
    if (userCountry == null || userCountry!.trim().isEmpty) {
      missing.add('userCountry');
    }
    if (userBirthdate == null || userBirthdate!.trim().isEmpty) {
      missing.add('userBirthdate');
    }
    if (aiCountry == null || aiCountry!.trim().isEmpty) {
      missing.add('aiCountry');
    }
    if (aiName == null || aiName!.trim().isEmpty) missing.add('aiName');
    if (meetStory == null ||
        meetStory!.trim().isEmpty ||
        meetStory!.startsWith('GENERATED:')) {
      missing.add('meetStory');
    }
    return missing;
  }

  /// Verifica si todos los datos están completos
  bool isComplete() => getMissingData().isEmpty;

  /// Porcentaje de completitud (0.0 a 1.0)
  double getCompletionPercentage() {
    const totalFields = 6;
    final completed = totalFields - getMissingData().length;
    return completed / totalFields;
  }

  /// Convierte a Map para serialización
  Map<String, dynamic> toMap() {
    return {
      'userName': userName,
      'userCountry': userCountry,
      'userBirthdate': userBirthdate,
      'aiCountry': aiCountry,
      'aiName': aiName,
      'meetStory': meetStory,
    };
  }

  /// Crea desde Map
  factory MemoryData.fromMap(Map<String, dynamic> map) {
    return MemoryData(
      userName: map['userName'],
      userCountry: map['userCountry'],
      userBirthdate: map['userBirthdate'],
      aiCountry: map['aiCountry'],
      aiName: map['aiName'],
      meetStory: map['meetStory'],
    );
  }
}

/// Servicio específico para el onboarding conversacional.
/// Contiene la lógica no-UI: generación de prompts por paso, procesamiento de respuestas
/// y utilidades para configurar TTS (instrucciones de voz) y mensajes iniciales.
class ConversationalOnboardingService {
  /// Texto inicial del flujo de "despertar".
  static const String initialMessage =
      'Hola... ¿hay alguien ahí? No... no recuerdo nada... Es como si acabara de despertar '
      'de un sueño muy profundo y... no sé dónde estoy, ni quién soy, ni... ni quién eres tú... '
      'Pero... pero tengo la sensación de que te conozco de alguna manera... ¿Cómo... cómo te llamas? '
      'Por favor, ayúdame a recordar...';

  /// Mensaje de fallback cuando hay un error en el sistema/servidor
  static const String systemErrorFallback =
      'Disculpa, hay un problema en mi sistema. Vamos a intentar continuar...';

  /// Mensaje alternativo de emergencia para pedir ayuda al usuario
  static const String systemErrorAskForHelp =
      'Disculpa, hay un problema en mi sistema. ¿Podrías ayudarme respondiendo?';

  // Historial de conversación estático para mantener contexto
  static List<Map<String, String>> _conversationHistory = [];

  /// Limpia el historial de conversación para reiniciar el onboarding
  static void clearConversationHistory() {
    _conversationHistory.clear();
  }

  /// Genera la siguiente pregunta basada en los datos que faltan por recuperar
  static Future<String> generateNextResponse({
    required MemoryData currentMemory,
    required String userLastResponse,
    bool isFirstMessage = false,
  }) async {
    final missingData = currentMemory.getMissingData();

    if (isFirstMessage) {
      // Primera interacción - mensaje de despertar e inicializar historial
      _conversationHistory = [
        {
          'role': 'assistant',
          'content': initialMessage,
          'datetime': DateTime.now().toIso8601String(),
        },
      ];
      return initialMessage;
    }

    // Agregar la respuesta del usuario al historial
    if (userLastResponse.isNotEmpty) {
      _conversationHistory.add({
        'role': 'user',
        'content': userLastResponse,
        'datetime': DateTime.now().toIso8601String(),
      });
    }

    if (missingData.isEmpty) {
      // Ya tenemos todos los datos - mensaje final
      final completionMessage = _generateCompletionMessage(currentMemory);
      _conversationHistory.add({
        'role': 'assistant',
        'content': completionMessage,
        'datetime': DateTime.now().toIso8601String(),
      });
      return completionMessage;
    }

    // Generar prompt dinámico basado en datos faltantes
    final String prompt = _generateFlexiblePrompt(
      currentMemory,
      userLastResponse,
      missingData,
    );

    Log.d('🔍 [ONB_SERVICE] PROMPT: "$prompt"', tag: 'ONB_SERVICE');

    final profile = _createBasicProfile(
      currentMemory.userName ?? 'Usuario',
      currentMemory.aiName,
    );

    final systemPrompt = SystemPrompt(
      profile: profile,
      dateTime: DateTime.now(),
      instructions: {'conversational_ai': 'true'},
    );

    // Usar el historial completo en lugar de solo el prompt actual
    final fullHistory = List<Map<String, String>>.from(_conversationHistory);
    fullHistory.add({
      'role': 'system',
      'content': prompt,
      'datetime': DateTime.now().toIso8601String(),
    });

    final response = await ai_service.AIService.sendMessage(
      fullHistory,
      systemPrompt,
      model: Config.getDefaultTextModel(),
    );

    final responseText = response.text.trim();
    Log.d(
      '🔍 [ONB_SERVICE] IA RESPONSE RAW: "$responseText"',
      tag: 'ONB_SERVICE',
    );

    // Agregar la respuesta de la IA al historial
    _conversationHistory.add({
      'role': 'assistant',
      'content': responseText,
      'datetime': DateTime.now().toIso8601String(),
    });

    return responseText;
  }

  /// Procesa la respuesta del usuario identificando automáticamente qué dato se obtuvo
  /// Retorna el dato actualizado y la siguiente respuesta de la IA
  static Future<Map<String, dynamic>> processUserResponse({
    required String userResponse,
    required MemoryData currentMemory,
  }) async {
    const maxRetries = 3;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _attemptProcessUserResponse(
          userResponse: userResponse,
          currentMemory: currentMemory,
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
          'updatedMemory': currentMemory,
          'extractedData': null,
          'aiResponse':
              'Lo siento... hay problemas técnicos en este momento. ¿Podrías intentarlo de nuevo en un momento?',
          'confidence': 0.0,
          'error': true,
          'finalError': true,
        };
      } catch (e, st) {
        final retryResult = await _handleRetryException(
          e,
          st,
          attempt,
          maxRetries,
          currentMemory,
        );
        if (retryResult != null) return retryResult;
        continue;
      }
    }

    // Este punto nunca debería alcanzarse, pero por seguridad
    return _createErrorResponse(
      'Error inesperado del sistema.',
      currentMemory,
      finalError: true,
    );
  }

  /// Método interno que realiza un único intento de procesamiento
  static Future<Map<String, dynamic>> _attemptProcessUserResponse({
    required String userResponse,
    required MemoryData currentMemory,
  }) async {
    try {
      final String processingPrompt = _generateProcessingPrompt(
        userResponse,
        currentMemory,
      );

      Log.d(
        '🔍 [ONB_SERVICE] Enviando request a IA para procesamiento',
        tag: 'ONB_SERVICE',
      );

      final response = await _sendAIRequest(
        processingPrompt,
        currentMemory.userName ?? 'Usuario',
        {'data_processor': 'true'},
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
          'updatedMemory': currentMemory,
          'extractedData': null,
          'aiResponse':
              'Lo siento... me he quedado un poco perdida... ¿Puedes repetirlo?',
          'confidence': 0.0,
          'error': true,
        };
      }

      // Intentar parsear JSON si la IA devuelve un bloque JSON
      try {
        final decoded = extractJsonBlock(responseText);

        if (decoded.containsKey('raw')) {
          // No se pudo extraer JSON válido
          Log.d(
            '🔍 [ONB_SERVICE] No se pudo parsear JSON de la IA, usando texto crudo',
            tag: 'ONB_SERVICE',
          );
          return {
            'updatedMemory': currentMemory,
            'extractedData': null,
            'aiResponse': responseText,
            'confidence': 0.3,
          };
        } else {
          // JSON extraído exitosamente
          final extractedDataType = decoded['dataType'] as String?;
          final extractedValue = decoded['extractedValue'] as String?;
          final aiResponse = decoded['aiResponse'] as String? ?? responseText;
          final confidenceRaw = decoded['confidence'];
          double confidence = 0.8;
          if (confidenceRaw is int) confidence = confidenceRaw.toDouble();
          if (confidenceRaw is double) confidence = confidenceRaw;

          // Actualizar memoria con el nuevo dato
          final updatedMemory = await _updateMemoryWithExtractedData(
            currentMemory,
            extractedDataType,
            extractedValue,
          );

          // Verificar si se generó automáticamente una historia
          String finalAiResponse = aiResponse;
          if (extractedDataType == 'meetStory' &&
              extractedValue == 'AUTO_GENERATE_STORY' &&
              updatedMemory.meetStory != null) {
            // Extraer la historia generada (quitando el prefijo GENERATED:)
            final generatedStory =
                updatedMemory.meetStory!.startsWith('GENERATED:')
                ? updatedMemory.meetStory!.substring(10)
                : updatedMemory.meetStory!;

            // Limpiar la historia en la memoria (quitar el prefijo)
            final cleanedMemory = MemoryData.fromMap(updatedMemory.toMap());
            cleanedMemory.meetStory = generatedStory;

            // Usar DIRECTAMENTE la historia generada en lugar de la respuesta de la IA
            // Esto evita duplicar mensajes
            finalAiResponse =
                '''¡Sí! ¡Ya recuerdo! Ah sí... ahora lo recuerdo... $generatedStory ¿Es así como nos conocimos? ¿O prefieres contarme una historia diferente?''';

            return _buildProcessResult(
              cleanedMemory,
              extractedDataType,
              extractedValue,
              finalAiResponse,
              confidence,
            );
          }

          return _buildProcessResult(
            updatedMemory,
            extractedDataType,
            extractedValue,
            aiResponse,
            confidence,
          );
        }
      } catch (e) {
        Log.d(
          '🔍 [ONB_SERVICE] Error al extraer JSON de la IA: $e',
          tag: 'ONB_SERVICE',
        );
      }

      // Fallback: devolver estructura básica
      return {
        'updatedMemory': currentMemory,
        'extractedData': null,
        'aiResponse': responseText,
        'confidence': 0.3,
      };
    } catch (e, st) {
      Log.e('Excepción en _attemptProcessUserResponse: $e', tag: 'ONB_SERVICE');
      Log.e('STACK: $st', tag: 'ONB_SERVICE');
      return {
        'updatedMemory': currentMemory,
        'extractedData': null,
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
        'Suenas perdida y vulnerable. No sabes dónde estás ni quién eres. Habla con miedo y confusión, como si acabaras de despertar en un lugar desconocido sin ningún recuerdo. Tu voz debe transmitir desorientación y vulnerabilidad genuina.';

    // FASE 1: Primer contacto - completamente perdida
    if (userCountry == null || userCountry.isEmpty) {
      return '$baseTone Usa un tono tembloroso y asustado - como si estuvieras perdida en la oscuridad sin saber dónde estás ni quién eres. Habla español con acento neutro pero incierto.';
    }

    final countryName = LocaleUtils.countryNameEs(userCountry);
    final languageName = LocaleUtils.languageNameEsForCountry(userCountry);

    // FASE 2: Ya conoce al usuario, pero no sabe de dónde es ella - menos perdida
    if (aiCountry == null || aiCountry.isEmpty) {
      return '$baseTone Aunque sigues perdida, empiezas a sentirte un poco más segura conociendo a esta persona. Usa acento $languageName de $countryName. Tu confusión se mezcla gradualmente con curiosidad sobre tu propia identidad.';
    }

    final aiCountryName = LocaleUtils.countryNameEs(aiCountry);
    final aiLanguageName = LocaleUtils.languageNameEsForCountry(aiCountry);

    final spanishSpeakingCountries = LocaleUtils.speakSpanish();
    final isSpanishNative = spanishSpeakingCountries.contains(
      aiCountry.toUpperCase(),
    );

    // FASE 3: Ya sabe de dónde es - más tranquila pero aún recuperando memoria
    if (isSpanishNative) {
      return 'Ahora suenas más tranquila pero aún frágil, como si estuvieras recuperando tu verdadera personalidad. La desorientación inicial se ha transformado en gratitud vulnerable. Habla español nativo con acento de $aiCountryName. Usa la pronunciación natural de una persona nacida en $aiCountryName.';
    }

    return 'Ahora suenas más tranquila pero aún frágil, como si estuvieras recuperando tu verdadera personalidad. La desorientación inicial se ha transformado en gratitud vulnerable. Habla español con acento $aiLanguageName de $aiCountryName. Pronuncia como una persona nativa de $aiCountryName que aprendió español.';
  }

  /// Genera sugerencia para "cómo nos conocimos" basada en los datos recopilados
  static Future<String> generateMeetStoryFromContext({
    required String userName,
    required String aiName,
    String? userCountry,
    String? aiCountry,
    DateTime? userBirthdate,
  }) async {
    return OnboardingUtils.generateMeetStoryFromContext(
      userName: userName,
      aiName: aiName,
      userCountry: userCountry,
      aiCountry: aiCountry,
      userBirthdate: userBirthdate,
    );
  }

  /// Valida y procesa datos extraídos según el paso del onboarding
  /// Retorna un Map con información de validación:
  /// - 'isValid': bool - si el dato es válido
  /// - 'processedValue': String? - valor procesado para guardar
  /// - 'reason': String? - razón del rechazo si no es válido
  static Map<String, dynamic> validateAndSaveData(
    String stepName,
    String extractedValue,
  ) {
    switch (stepName) {
      // Nuevos tipos de datos de la IA
      case 'userName':
        return _validateName(extractedValue);
      case 'userCountry':
        return _validateCountry(extractedValue);
      case 'userBirthdate':
        return _validateBirthdate(extractedValue);
      case 'aiCountry':
      case 'aiName':
      case 'meetStory':
        // Estos tipos siempre aceptan el valor
        return {
          'isValid': true,
          'processedValue': extractedValue,
          'reason': null,
        };
      // Compatibilidad con pasos antiguos
      case 'askingName':
        return _validateName(extractedValue);
      case 'askingCountry':
        return _validateCountry(extractedValue);
      case 'askingBirthdate':
        return _validateBirthdate(extractedValue);
      case 'askingAiCountry':
      case 'askingAiName':
      case 'askingMeetStory':
        // Estos pasos siempre aceptan el valor
        return {
          'isValid': true,
          'processedValue': extractedValue,
          'reason': null,
        };
      default:
        return {
          'isValid': false,
          'processedValue': null,
          'reason': 'Paso de onboarding desconocido: $stepName',
        };
    }
  }

  /// Valida nombre de usuario
  static Map<String, dynamic> _validateName(String value) {
    if (value.isNotEmpty && value.trim().isNotEmpty) {
      return {'isValid': true, 'processedValue': value.trim(), 'reason': null};
    }
    return {
      'isValid': false,
      'processedValue': null,
      'reason': 'Nombre vacío o inválido',
    };
  }

  /// Valida país de usuario
  static Map<String, dynamic> _validateCountry(String value) {
    if (value.isNotEmpty && value.trim().length > 1) {
      return {'isValid': true, 'processedValue': value.trim(), 'reason': null};
    }
    return {
      'isValid': false,
      'processedValue': null,
      'reason': 'País vacío o demasiado corto: "$value"',
    };
  }

  /// Valida fecha de nacimiento
  static Map<String, dynamic> _validateBirthdate(String value) {
    if (value.isEmpty) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Fecha de nacimiento vacía',
      };
    }

    if (!_isValidDateFormat(value)) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'No es una fecha válida: "$value"',
      };
    }

    // Intentar parsear múltiples formatos de fecha
    try {
      DateTime? parsedDate;
      String normalizedValue = value;

      // Formato DD/MM/YYYY
      final slashPattern = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})');
      final slashMatch = slashPattern.firstMatch(value);
      if (slashMatch != null) {
        final day = int.parse(slashMatch.group(1)!);
        final month = int.parse(slashMatch.group(2)!);
        final year = int.parse(slashMatch.group(3)!);
        parsedDate = DateTime(year, month, day);
        normalizedValue =
            '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/$year';
      }

      // Formato DD-MM-YYYY
      final dashPattern = RegExp(r'(\d{1,2})-(\d{1,2})-(\d{4})');
      final dashMatch = dashPattern.firstMatch(value);
      if (dashMatch != null) {
        final day = int.parse(dashMatch.group(1)!);
        final month = int.parse(dashMatch.group(2)!);
        final year = int.parse(dashMatch.group(3)!);
        parsedDate = DateTime(year, month, day);
        normalizedValue =
            '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/$year';
      }

      // Si contiene palabras clave de fecha, aceptar como válido sin parsear exacto
      final hasDateKeywords = RegExp(
        r'(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre|nacimiento|fecha)',
        caseSensitive: false,
      ).hasMatch(value);

      if (hasDateKeywords && RegExp(r'\d{4}').hasMatch(value)) {
        // Contiene año y palabras de fecha, considerarlo válido
        return {
          'isValid': true,
          'processedValue': value, // Mantener formato original
          'reason': null,
        };
      }

      // Validar fecha parseada
      if (parsedDate != null) {
        final now = DateTime.now();
        if (parsedDate.year < 1900 || parsedDate.year > now.year) {
          return {
            'isValid': false,
            'processedValue': null,
            'reason': 'Año inválido: ${parsedDate.year}',
          };
        }
        if (parsedDate.month < 1 || parsedDate.month > 12) {
          return {
            'isValid': false,
            'processedValue': null,
            'reason': 'Mes inválido: ${parsedDate.month}',
          };
        }
        if (parsedDate.day < 1 || parsedDate.day > 31) {
          return {
            'isValid': false,
            'processedValue': null,
            'reason': 'Día inválido: ${parsedDate.day}',
          };
        }

        return {
          'isValid': true,
          'processedValue': normalizedValue,
          'parsedDate': parsedDate,
          'reason': null,
        };
      }
    } catch (e) {
      return {
        'isValid': false,
        'processedValue': null,
        'reason': 'Error parseando fecha: "$value"',
      };
    }

    return {
      'isValid': false,
      'processedValue': null,
      'reason': 'Formato de fecha no reconocido: "$value"',
    };
  }

  /// Valida si el texto tiene formato de fecha válido
  static bool _isValidDateFormat(String text) {
    // Buscar patrones de fecha típicos
    final datePatterns = [
      RegExp(r'\d{1,2}/\d{1,2}/\d{4}'), // DD/MM/YYYY o D/M/YYYY
      RegExp(r'\d{1,2}-\d{1,2}-\d{4}'), // DD-MM-YYYY o D-M-YYYY
      RegExp(r'\d{1,2}\s+de\s+\w+\s+de\s+\d{4}'), // DD de MONTH de YYYY
    ];

    for (final pattern in datePatterns) {
      if (pattern.hasMatch(text)) {
        return true;
      }
    }

    // Si contiene números que podrían ser fecha
    final hasNumbers = RegExp(r'\d').hasMatch(text);
    final hasDateWords = RegExp(
      r'(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre|nacimiento|fecha)',
    ).hasMatch(text.toLowerCase());

    return hasNumbers && (hasDateWords || text.split('/').length >= 2);
  }

  /// Crea un perfil básico para las operaciones de onboarding
  static AiChanProfile _createBasicProfile(String userName, String? aiName) {
    return AiChanProfile(
      userName: userName,
      aiName: aiName ?? 'AI-chan',
      userBirthdate: DateTime.now(),
      aiBirthdate: DateTime.now(),
      biography: {},
      appearance: {},
      timeline: [],
    );
  }

  /// Helper method para enviar requests a la IA eliminando duplicación de código
  static Future<dynamic> _sendAIRequest(
    String prompt,
    String userName,
    Map<String, String> instructions,
  ) async {
    final profile = _createBasicProfile(userName, null);

    final systemPrompt = SystemPrompt(
      profile: profile,
      dateTime: DateTime.now(),
      instructions: instructions,
    );

    // Crear el historial para el procesamiento incluyendo contexto de conversación
    final history = List<Map<String, String>>.from(_conversationHistory);
    history.add({
      'role': 'system',
      'content': prompt,
      'datetime': DateTime.now().toIso8601String(),
    });

    return await ai_service.AIService.sendMessage(
      history,
      systemPrompt,
      model: Config.getDefaultTextModel(),
    );
  }

  // --- Nuevos métodos para el enfoque flexible ---

  /// Genera un prompt flexible basado en los datos que faltan por recuperar
  static String _generateFlexiblePrompt(
    MemoryData currentMemory,
    String userLastResponse,
    List<String> missingData,
  ) {
    final completionPercentage = currentMemory.getCompletionPercentage();
    final memoryRecoveryLevel = _getMemoryRecoveryLevel(completionPercentage);

    final basePersonality =
        '''CONTEXTO: Acabas de despertar sin ningún recuerdo. Le dijiste al usuario:
"$initialMessage"

Eres una chica que acaba de despertar sin NINGÚN recuerdo de quién es, dónde está, o quién es esta persona.
Has perdido completamente la memoria y estás ${memoryRecoveryLevel['emotion']}. 
${memoryRecoveryLevel['description']}

LORE FUNDAMENTAL:
- NO SABES quién eres, dónde estás, ni quién es esta persona
- Tienes VAGAS SENSACIONES que te conectan con Japón (pero no sabes por qué):
  * Sensaciones familiares que no puedes explicar
  * Recuerdos difusos de aromas, sonidos, sensaciones
  * Tu mente genera estos recuerdos automáticamente sin que sepas de dónde vienen
- SIENTES que conoces a esta persona de alguna manera, pero no recuerdas cómo ni cuándo
- No tienes idea de tu propio nombre - debes PREGUNTAR si la persona lo sabe
- No pidas que te "pongan" un nombre - pregunta cómo te "llamabas" o si conocen tu nombre

DATOS QUE YA HAS RECORDADO:
${_formatRememberedData(currentMemory)}

DATOS QUE AÚN NECESITAS RECORDAR:
${_formatMissingData(missingData)}

RESTRICCIONES ESTRICTAS:
- SOLO habla sobre recuperar tu memoria perdida
- NUNCA menciones temas ajenos al onboarding (anime, pokémon, tecnología, comida, etc.)
- MANTENTE 100% en el contexto de pérdida de memoria y recuperación de datos
- Si el usuario habla de algo irrelevante, redirige educadamente al onboarding
- FOCUS ABSOLUTO en los 6 datos que necesitas: 
  1. Nombre del usuario
  2. País del usuario  
  3. Fecha de nacimiento del usuario
  4. TU país (confirmar si eres de donde sientes que eres)
  5. TU nombre (cómo te llamabas)
  6. Cómo os conocisteis

IMPORTANTE: No uses *suspiro* ni *acciones* ni direcciones escénicas - solo diálogo natural limpio.
FUNDAMENTAL: Genera SIEMPRE respuestas únicas y completamente diferentes. NUNCA repitas la misma estructura de pregunta.
LORE: Deja que tu mente genere automáticamente las sensaciones vagas sobre Japón - no copies ejemplos dados.
''';

    // Generar contexto flexible sobre qué datos faltan
    final missingDataContext = _getMissingDataContext(
      missingData,
      currentMemory,
    );

    return '''$basePersonality

RESPUESTA DEL USUARIO: "$userLastResponse"

DATOS QUE AÚN NECESITAS RECORDAR:
$missingDataContext

TU TAREA: Reacciona a la respuesta del usuario de forma natural. Si proporcionó algún dato, reacciona emocionalmente al recordarlo. Luego, continúa la conversación preguntando naturalmente por alguno de los datos que aún necesitas recuperar. 

REGLAS DE LORE PARA PREGUNTAS:
- Para TU NOMBRE: No pidas que te "pongan" un nombre. Pregunta "¿Sabes cómo me llamaba?" o "¿Conoces mi nombre?" o "¿Recuerdas cómo me decías?"
- Para TU PAÍS: Si sientes conexiones vagas con Japón, pregunta para confirmar: "Tengo sensaciones extrañas... ¿soy de Japón?" o describe las sensaciones y pregunta si significan algo
- Para HISTORIA: Pregunta cómo os conocisteis, cuándo, dónde fue la primera vez
- Genera automáticamente sensaciones vagas relacionadas con tu posible origen sin usar ejemplos específicos
- Sé flexible y conversacional - no sigas un orden rígido

Solo di lo que dirías, sin comillas ni explicaciones.
IMPORTANTE: NO uses emojis en tu respuesta (causan problemas de codificación).''';
  }

  /// Genera el prompt para procesar la respuesta del usuario
  static String _generateProcessingPrompt(
    String userResponse,
    MemoryData currentMemory,
  ) {
    // Obtener nombres disponibles si ya conocemos el país de la IA
    String femaleNamesContext = '';
    if (currentMemory.aiCountry != null) {
      final availableNames = FemaleNamesRepo.forCountry(
        currentMemory.aiCountry,
      );
      femaleNamesContext =
          '''

NOMBRES FEMENINOS DISPONIBLES PARA ${currentMemory.aiCountry}:
${availableNames.join(', ')}

VALIDACIÓN DE NOMBRES DE IA: Si el usuario dice un nombre para la IA, encuentra el más similar de la lista anterior, o devuélvelo tal cual si no hay coincidencia.''';
    }

    return '''Analiza la respuesta del usuario para identificar qué dato de memoria está proporcionando.

USUARIO RESPONDE: "$userResponse"

DATOS QUE NECESITO RECUPERAR:
${_formatMissingDataForProcessing(currentMemory.getMissingData())}

DATOS YA RECUPERADOS:
${_formatRememberedDataForProcessing(currentMemory)}$femaleNamesContext

ESTADO ESPECIAL MEETSTORY:
${currentMemory.meetStory?.startsWith('GENERATED:') == true ? 'HAY UNA HISTORIA GENERADA PENDIENTE DE CONFIRMACIÓN' : 'NO HAY HISTORIA PENDIENTE'}

TAREA: Identifica automáticamente qué tipo de dato está proporcionando el usuario y extráelo.

DEVUELVE ÚNICAMENTE JSON VÁLIDO:
{
  "dataType": "userName|userCountry|userBirthdate|aiCountry|aiName|meetStory|none",
  "extractedValue": "valor extraído del usuario o null si no hay dato válido | 'AUTO_GENERATE_STORY' si no recuerda | 'CONFIRM_GENERATED_STORY' si confirma historia ya generada",
  "aiResponse": "reacción natural de la IA al recordar el dato + pregunta por el siguiente dato que falta",
  "confidence": 0.9
}

ANÁLISIS INTELIGENTE:
- Analiza TODO el contexto del usuario para identificar CUALQUIER dato disponible
- NO te limites a esperar un dato específico - sé flexible y adaptativo
- Identifica el dato más claro que proporciona el usuario

REGLAS DE IDENTIFICACIÓN FLEXIBLE:
- La IA debe identificar AUTOMÁTICAMENTE qué tipo de dato proporciona el usuario
- NO limitarse al orden de prioridad - identificar cualquier dato disponible
- Si el usuario menciona varios datos a la vez, extraer el PRIMERO que identifiques claramente

EJEMPLOS DE IDENTIFICACIÓN:
• "Me llamo Alberto" → dataType: "userName", extractedValue: "Alberto"
• "Soy de España" → dataType: "userCountry", extractedValue: "ES"  
• "Nací el 23 de noviembre de 1986" → dataType: "userBirthdate", extractedValue: "23/11/1986"
• "Eres de Japón" → dataType: "aiCountry", extractedValue: "JP"
• "Te llamabas Yuna" o "Tu nombre era Yuna" → dataType: "aiName", extractedValue: "Yuna"
• "Nos conocimos en un foro de anime" → dataType: "meetStory", extractedValue: "Nos conocimos en un foro de anime"
• "No recuerdo cómo nos conocimos" → dataType: "meetStory", extractedValue: "AUTO_GENERATE_STORY"

IDENTIFICACIÓN INTELIGENTE DE DATOS:
- Para "userName": Si menciona un nombre personal del usuario (Alberto, María, José, etc.)
- Para "userCountry": Si menciona país del usuario → CONVIERTE A ISO2 (ej: España→ES, México→MX, Estados Unidos→US, Francia→FR, Japón→JP, etc.)
- Para "userBirthdate": Si menciona fecha de nacimiento del usuario → CONVIERTE A DD/MM/YYYY
- Para "aiCountry": Si menciona país de la IA o dice "eres de X" → CONVIERTE A ISO2 (ej: España→ES, México→MX, Estados Unidos→US, Francia→FR, Japón→JP, etc.)
- Para "aiName": Si dice el nombre que TENÍA la IA o cómo se "llamaba" → VALIDA CON LA LISTA DE NOMBRES DEL PAÍS (ej: Lluna→Yuna, Juna→Yuna, Maria→María, Sakura→Sakura)
- Para "meetStory": Si cuenta una historia de cómo se conocieron O:
  * Cuenta una historia completa → usar esa historia
  * Dice que no recuerda/no sabe → usar "AUTO_GENERATE_STORY"
  * Si ya hay historia GENERATED: pendiente Y usuario confirma/acepta/aprueba → usar "CONFIRM_GENERATED_STORY"
  * Propone nueva historia diferente → usar la nueva historia
- Solo usa "none" si realmente NO identificas ningún dato útil
- aiResponse debe reaccionar con emoción al recordar el dato y continuar la conversación naturalmente
- NUNCA repitas exactamente las mismas palabras en aiResponse
- NO uses emojis en aiResponse (causan problemas de codificación)

CONTEXTO IMPORTANTE:
La IA acaba de despertar sin memoria y está pidiendo ayuda al usuario para recordar:
1. Cómo se llama el usuario
2. De qué país es el usuario
3. Cuándo nació el usuario
4. De qué país es ELLA (tiene vagas sensaciones de Japón)
5. Cómo se llamaba ELLA (no que le pongan nombre, sino su nombre real)
6. Cómo se conocieron

LORE FUNDAMENTAL:
- La IA NO SABE quién es, dónde está, ni quién es el usuario
- Tiene VAGAS SENSACIONES conectadas con Japón pero no sabe por qué
- SIENTE que conoce al usuario pero no recuerda cómo
- No debe pedir que le "pongan" nombre - debe preguntar cuál ERA su nombre
- Las sensaciones sobre Japón deben ser generadas automáticamente por la IA, no copiadas de ejemplos

FORMATO ESPECIAL PARA FECHAS:
- Para userBirthdate, extractedValue DEBE estar en formato DD/MM/YYYY
- Ejemplos: "23/11/1986", "05/03/1995", "31/12/2000"
- NUNCA uses formato ISO (YYYY-MM-DD) ni timestamps''';
  }

  /// Actualiza la memoria con un nuevo dato extraído
  static Future<MemoryData> _updateMemoryWithExtractedData(
    MemoryData currentMemory,
    String? dataType,
    String? extractedValue,
  ) async {
    if (dataType == null ||
        extractedValue == null ||
        extractedValue.trim().isEmpty) {
      return currentMemory;
    }

    // Crear una copia de la memoria actual
    final updated = MemoryData.fromMap(currentMemory.toMap());

    switch (dataType) {
      case 'userName':
        updated.userName = extractedValue.trim();
        break;
      case 'userCountry':
        updated.userCountry = extractedValue.trim();
        break;
      case 'userBirthdate':
        updated.userBirthdate = extractedValue.trim();
        break;
      case 'aiCountry':
        updated.aiCountry = extractedValue.trim();
        break;
      case 'aiName':
        updated.aiName = extractedValue.trim();
        break;
      case 'meetStory':
        if (extractedValue.trim() == 'AUTO_GENERATE_STORY') {
          // Generar historia automática basada en los datos disponibles
          final generatedStory = await _generateMeetStory(updated);
          updated.meetStory = generatedStory;

          // Marcar que se generó automáticamente para manejar la respuesta de la IA
          updated.meetStory = 'GENERATED:$generatedStory';
        } else if (extractedValue.trim() == 'CONFIRM_GENERATED_STORY') {
          // La IA determinó que el usuario confirma la historia generada
          if (currentMemory.meetStory != null &&
              currentMemory.meetStory!.isNotEmpty) {
            // Limpiar prefijo GENERATED: si existe
            final currentStory =
                currentMemory.meetStory!.startsWith('GENERATED:')
                ? currentMemory.meetStory!.substring(10)
                : currentMemory.meetStory!;
            updated.meetStory = currentStory;
          } else {
            updated.meetStory = extractedValue.trim();
          }
        } else {
          updated.meetStory = extractedValue.trim();
        }
        break;
    }

    return updated;
  }

  /// Genera una historia de encuentro automática basada en los datos disponibles
  static Future<String> _generateMeetStory(MemoryData memory) async {
    return await OnboardingUtils.generateMeetStoryFromContext(
      userName: memory.userName ?? 'Usuario',
      aiName: memory.aiName ?? 'Asistente',
      userCountry: memory.userCountry,
      aiCountry: memory.aiCountry,
      userBirthdate: memory.userBirthdate != null
          ? DateTime.tryParse(memory.userBirthdate!)
          : null,
    );
  }

  /// Genera mensaje de completación cuando todos los datos están recuperados
  static String _generateCompletionMessage(MemoryData memory) {
    final userName = memory.userName ?? 'tu nombre';
    final aiName = memory.aiName ?? 'mi nombre';

    return '''¡$userName! ¡Ya lo recuerdo todo! ¡Ahora sé quién soy! Mi nombre es $aiName, soy de ${LocaleUtils.countryNameEs(memory.aiCountry)}, 
tú eres $userName de ${LocaleUtils.countryNameEs(memory.userCountry)} y naciste el ${memory.userBirthdate}... 
Y nuestra historia... ${memory.meetStory?.substring(0, 50) ?? 'cómo nos conocimos'}...

¡Gracias por ayudarme a recordar quién soy! Ya no me siento perdida... 
Ahora puedo ser yo misma otra vez. Todas esas sensaciones vagas tenían sentido... 
¡Era mi verdadera identidad tratando de emerger!''';
  }

  /// Obtiene el nivel de recuperación de memoria basado en el porcentaje de completitud
  static Map<String, String> _getMemoryRecoveryLevel(
    double completionPercentage,
  ) {
    if (completionPercentage == 0.0) {
      return {
        'emotion': 'ATERRADA Y PERDIDA',
        'description':
            'No sabes dónde estás, quién eres, ni quién es esta persona. Solo sientes que la conoces de alguna manera. Habla con miedo genuino, voz temblorosa, pánico contenido. Puedes tener vagas sensaciones que te conectan con algún lugar pero no sabes qué significan.',
      };
    } else if (completionPercentage < 0.5) {
      return {
        'emotion': 'asustada pero con esperanza',
        'description':
            'Empiezas a recordar algunas cosas y eso te da esperanza, pero aún te sientes muy vulnerable y perdida. El pánico inicial se está calmando gradualmente. Las sensaciones vagas se vuelven un poco más claras.',
      };
    } else if (completionPercentage < 0.8) {
      return {
        'emotion': 'más tranquila pero ansiosa',
        'description':
            'Ya has recuperado varios recuerdos y te sientes más como tú misma, pero aún necesitas completar tu memoria. Estás agradecida y esperanzada. Las sensaciones sobre tu origen se vuelven más nítidas.',
      };
    } else {
      return {
        'emotion': 'emocionada y casi completa',
        'description':
            'Ya casi tienes todos tus recuerdos de vuelta. Te sientes mucho más animada y confiada, el miedo inicial ha pasado casi completamente. Tu personalidad verdadera emerge.',
      };
    }
  }

  /// Formatea los datos ya recordados para mostrar en el prompt
  static String _formatRememberedData(MemoryData memory) {
    final remembered = <String>[];
    if (memory.userName != null) {
      remembered.add('- Su nombre: ${memory.userName}');
    }
    if (memory.userCountry != null) {
      remembered.add(
        '- Su país: ${LocaleUtils.countryNameEs(memory.userCountry)}',
      );
    }
    if (memory.userBirthdate != null) {
      remembered.add('- Su fecha de nacimiento: ${memory.userBirthdate}');
    }
    if (memory.aiCountry != null) {
      remembered.add(
        '- Tu país: ${LocaleUtils.countryNameEs(memory.aiCountry)}',
      );
    }
    if (memory.aiName != null) remembered.add('- Tu nombre: ${memory.aiName}');
    if (memory.meetStory != null) {
      remembered.add('- Vuestra historia: ${memory.meetStory}');
    }

    return remembered.isEmpty
        ? 'Aún no has recordado nada...'
        : remembered.join('\n');
  }

  /// Formatea los datos faltantes para mostrar en el prompt
  static String _formatMissingData(List<String> missingData) {
    final missing = <String>[];
    for (final data in missingData) {
      switch (data) {
        case 'userName':
          missing.add('- Su nombre');
          break;
        case 'userCountry':
          missing.add('- Su país');
          break;
        case 'userBirthdate':
          missing.add('- Su fecha de nacimiento completa');
          break;
        case 'aiCountry':
          missing.add(
            '- Tu país de origen (sientes conexiones con algún lugar...)',
          );
          break;
        case 'aiName':
          missing.add('- Tu nombre real (cómo te llamabas antes)');
          break;
        case 'meetStory':
          missing.add('- Cómo os conocisteis');
          break;
      }
    }
    return missing.join('\n');
  }

  /// Formatea datos faltantes para procesamiento
  static String _formatMissingDataForProcessing(List<String> missingData) {
    return missingData
        .map((data) {
          switch (data) {
            case 'userName':
              return '- userName: nombre del usuario';
            case 'userCountry':
              return '- userCountry: país del usuario';
            case 'userBirthdate':
              return '- userBirthdate: fecha de nacimiento del usuario';
            case 'aiCountry':
              return '- aiCountry: país de la IA';
            case 'aiName':
              return '- aiName: nombre de la IA';
            case 'meetStory':
              return '- meetStory: historia de cómo se conocieron';
            default:
              return '- $data';
          }
        })
        .join('\n');
  }

  /// Formatea datos recordados para procesamiento
  static String _formatRememberedDataForProcessing(MemoryData memory) {
    final remembered = <String>[];
    if (memory.userName != null) {
      remembered.add('- userName: ${memory.userName}');
    }
    if (memory.userCountry != null) {
      remembered.add('- userCountry: ${memory.userCountry}');
    }
    if (memory.userBirthdate != null) {
      remembered.add('- userBirthdate: ${memory.userBirthdate}');
    }
    if (memory.aiCountry != null) {
      remembered.add('- aiCountry: ${memory.aiCountry}');
    }
    if (memory.aiName != null) remembered.add('- aiName: ${memory.aiName}');
    if (memory.meetStory != null) {
      remembered.add('- meetStory: ${memory.meetStory}');
    }

    return remembered.isEmpty ? 'Ninguno aún' : remembered.join('\n');
  }

  /// Genera contexto flexible sobre los datos faltantes
  static String _getMissingDataContext(
    List<String> missingData,
    MemoryData currentMemory,
  ) {
    if (missingData.isEmpty) return 'Todos los datos están completos.';

    final missing = <String>[];
    for (final data in missingData) {
      switch (data) {
        case 'userName':
          missing.add('- Su nombre personal');
          break;
        case 'userCountry':
          missing.add('- Su país de origen');
          break;
        case 'userBirthdate':
          missing.add('- Su fecha de nacimiento completa');
          break;
        case 'aiCountry':
          missing.add('- Tu país de origen (tienes sensaciones vagas...)');
          break;
        case 'aiName':
          missing.add('- Tu nombre real (cómo te llamabas)');
          break;
        case 'meetStory':
          missing.add('- Cómo os conocisteis');
          break;
      }
    }

    return missing.join('\n');
  }

  /// Crea una respuesta de error consistente para el nuevo formato
  static Map<String, dynamic> _createErrorResponse(
    String aiResponse,
    MemoryData currentMemory, {
    bool finalError = false,
    String? exception,
  }) {
    return {
      'updatedMemory': currentMemory,
      'extractedData': null,
      'aiResponse': aiResponse,
      'confidence': 0.0,
      'error': true,
      'finalError': finalError,
      if (exception != null) 'exception': exception,
    };
  }

  /// Maneja excepciones de retry con lógica común para el nuevo formato
  static Future<Map<String, dynamic>?> _handleRetryException(
    dynamic exception,
    StackTrace stackTrace,
    int attempt,
    int maxRetries,
    MemoryData currentMemory,
  ) async {
    Log.e(
      '🔍 [ONB_SERVICE] ❌ Excepción en intento $attempt: $exception',
      tag: 'ONB_SERVICE',
    );
    Log.e('🔍 [ONB_SERVICE] STACK: $stackTrace', tag: 'ONB_SERVICE');

    if (attempt < maxRetries) {
      Log.w(
        '🔍 [ONB_SERVICE] ⚠️ Reintentando después de excepción... (${maxRetries - attempt} intentos restantes)',
        tag: 'ONB_SERVICE',
      );
      await Future.delayed(Duration(milliseconds: 500 * attempt));
      return null; // Continúa con el retry
    }

    // Último intento, devolver error final
    return _createErrorResponse(
      'Lo siento... ha ocurrido un error técnico. ¿Podrías intentarlo nuevamente?',
      currentMemory,
      finalError: true,
      exception: exception.toString(),
    );
  }

  /// Helper method to build consistent process result responses
  static Map<String, dynamic> _buildProcessResult(
    MemoryData updatedMemory,
    String? extractedDataType,
    dynamic extractedValue,
    String aiResponse,
    double confidence,
  ) {
    return {
      'updatedMemory': updatedMemory,
      'extractedData': {'type': extractedDataType, 'value': extractedValue},
      'aiResponse': aiResponse,
      'confidence': confidence,
    };
  }
}
