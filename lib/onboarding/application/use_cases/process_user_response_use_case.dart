import 'package:ai_chan/shared.dart';
import 'package:ai_chan/onboarding/domain/entities/memory_data.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/onboarding/application/services/onboarding_utils.dart';

/// Caso de uso para procesar la respuesta del usuario durante el onboarding conversacional
class ProcessUserResponseUseCase {
  /// Procesa la respuesta del usuario identificando automáticamente qué dato se obtuvo
  /// Retorna el dato actualizado y la siguiente respuesta de la IA
  ///
  /// **Cambio DDD**: El historial ahora se pasa como parámetro desde el Application Service
  static Future<Map<String, dynamic>> execute({
    required final MemoryData currentMemory,
    required final String userResponse,
    required final List<Map<String, String>> conversationHistory,
    required final Function(String, String) addToHistory,
    final dynamic aiProviderManager, // Para testing
  }) async {
    const maxRetries = 3;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      Log.d(
        '🔍 [ONB_SERVICE] Intento $attempt/$maxRetries de procesamiento',
        tag: 'ONB_SERVICE',
      );

      try {
        final result = await _attemptProcessUserResponse(
          currentMemory: currentMemory,
          userResponse: userResponse,
          conversationHistory: conversationHistory,
          addToHistory: addToHistory,
          aiProviderManager: aiProviderManager,
        );

        Log.d(
          '✅ [ONB_SERVICE] Procesamiento exitoso en intento $attempt',
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
          return _createErrorResponse(
            'Todos los reintentos fallaron',
            currentMemory,
            userResponse,
          );
        }

        // Esperar antes del siguiente intento
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }

    // Este punto nunca debería alcanzarse, pero por seguridad
    return _createErrorResponse(
      'Error inesperado',
      currentMemory,
      userResponse,
    );
  }

  /// Método interno que realiza un único intento de procesamiento
  static Future<Map<String, dynamic>> _attemptProcessUserResponse({
    required final MemoryData currentMemory,
    required final String userResponse,
    required final List<Map<String, String>> conversationHistory,
    required final Function(String, String) addToHistory,
    final dynamic aiProviderManager,
  }) async {
    // Actualizar historial de conversación
    addToHistory('role', 'user');
    addToHistory('content', userResponse);
    addToHistory('datetime', DateTime.now().toIso8601String());

    // Identificar qué tipo de dato está proporcionando el usuario
    final prompt = _generateProcessingPrompt(userResponse, currentMemory);

    final instructions = {
      'role': 'system',
      'content':
          'Eres un asistente que analiza respuestas de usuarios para extraer datos específicos de onboarding.',
    };

    // Usar service para hacer la request
    final response = await _sendAIRequest(
      prompt,
      'Usuario',
      instructions,
      conversationHistory,
      aiProviderManager,
    );

    // Parsear respuesta JSON de la IA usando la función de utils
    dynamic responseData;
    try {
      Log.d('🔍 Respuesta original: "${response.text}"', tag: 'ONB_SERVICE');
      responseData = extractJsonBlock(response.text);

      // Si la función devolvió un objeto con 'raw', significa que no pudo parsear JSON válido
      if (responseData is Map<String, dynamic> &&
          responseData.containsKey('raw')) {
        Log.e(
          '❌ No se encontró JSON válido en la respuesta',
          tag: 'ONB_SERVICE',
        );
        return _createErrorResponse(
          'Error de parsing JSON',
          currentMemory,
          userResponse,
        );
      }

      Log.d('🔍 JSON parseado exitosamente', tag: 'ONB_SERVICE');
    } on Exception catch (e) {
      Log.e('❌ Error parseando JSON: $e', tag: 'ONB_SERVICE');
      Log.d('🔍 Respuesta original: "${response.text}"', tag: 'ONB_SERVICE');
      return _createErrorResponse(
        'Error de parsing JSON',
        currentMemory,
        userResponse,
      );
    }

    if (responseData == null) {
      Log.e('❌ Respuesta JSON nula o vacía', tag: 'ONB_SERVICE');
      return _createErrorResponse(
        'Respuesta IA vacía',
        currentMemory,
        userResponse,
      );
    }

    // Extraer datos de la respuesta
    final dataType = responseData['dataType'] as String?;
    final extractedValue = responseData['extractedValue'] as String?;
    final aiResponse = responseData['aiResponse'] as String?;
    final confidence = (responseData['confidence'] as num?)?.toDouble() ?? 0.0;

    Log.d(
      '🎯 IA extrajo: dataType=$dataType, value=$extractedValue, confidence=$confidence',
      tag: 'ONB_SERVICE',
    );

    // Actualizar memoria con el valor extraído
    final updateResult = await _updateMemoryWithExtractedData(
      dataType,
      extractedValue,
      currentMemory,
    );
    final updatedMemory = updateResult['memory'] as MemoryData;
    final newAiResponse = updateResult['aiResponse'] as String? ?? aiResponse;

    // Añadir respuesta de IA al historial si existe
    if (newAiResponse != null && newAiResponse.isNotEmpty) {
      addToHistory('role', 'assistant');
      addToHistory('content', newAiResponse);
      addToHistory('datetime', DateTime.now().toIso8601String());
    }

    return _buildProcessResult(
      updatedMemory: updatedMemory,
      extractedData: {'type': dataType, 'value': extractedValue},
      aiResponse: newAiResponse,
      confidence: confidence,
    );
  }

  /// Actualiza la memoria con un nuevo dato extraído
  static Future<Map<String, dynamic>> _updateMemoryWithExtractedData(
    final String? dataType,
    final String? extractedValue,
    final MemoryData currentMemory,
  ) async {
    if (dataType == null || extractedValue == null) {
      return {'memory': currentMemory, 'aiResponse': null};
    }

    // Manejar casos especiales
    if (extractedValue == 'AUTO_GENERATE_STORY') {
      // Generar historia automáticamente
      try {
        final generatedStory =
            await OnboardingUtils.generateMeetStoryFromContext(
              userName: currentMemory.userName ?? '',
              aiName: currentMemory.aiName ?? 'AI-chan',
              userCountry: currentMemory.userCountry,
              aiCountry: currentMemory.aiCountry,
              userBirthdate: currentMemory.userBirthdate != null
                  ? DateTime.tryParse(currentMemory.userBirthdate!)
                  : null,
            );

        final updatedMemory = currentMemory.copyWith(
          meetStory: 'GENERATED:$generatedStory',
        );
        final cleanStory = generatedStory.replaceAll('GENERATED:', '').trim();

        return {
          'memory': updatedMemory,
          'aiResponse':
              '¡Por fin lo recuerdo! $cleanStory ¿Te suena familiar? ¡Qué hermoso es recordar cómo comenzó todo!',
        };
      } on Exception catch (e) {
        Log.e('❌ Error generando historia: $e', tag: 'ONB_SERVICE');
        final fallbackMemory = currentMemory.copyWith(
          meetStory:
              'No puedo recordar exactamente cómo nos conocimos, pero sé que eres muy importante para mí.',
        );
        return {
          'memory': fallbackMemory,
          'aiResponse':
              'No puedo recordar exactamente cómo nos conocimos, pero sé que eres muy importante para mí.',
        };
      }
    }

    if (extractedValue == 'CONFIRM_GENERATED_STORY') {
      // Confirmar historia generada previamente
      if (currentMemory.meetStory?.startsWith('GENERATED:') == true) {
        final confirmedStory = currentMemory.meetStory!.substring(
          'GENERATED:'.length,
        );
        return {
          'memory': currentMemory.copyWith(meetStory: confirmedStory),
          'aiResponse': null,
        };
      }
      return {'memory': currentMemory, 'aiResponse': null};
    }

    // Actualizar campo específico
    switch (dataType) {
      case 'userName':
        return {
          'memory': currentMemory.copyWith(userName: extractedValue),
          'aiResponse': null,
        };
      case 'userCountry':
        return {
          'memory': currentMemory.copyWith(userCountry: extractedValue),
          'aiResponse': null,
        };
      case 'userBirthdate':
        return {
          'memory': currentMemory.copyWith(userBirthdate: extractedValue),
          'aiResponse': null,
        };
      case 'aiCountry':
        return {
          'memory': currentMemory.copyWith(aiCountry: extractedValue),
          'aiResponse': null,
        };
      case 'aiName':
        return {
          'memory': currentMemory.copyWith(aiName: extractedValue),
          'aiResponse': null,
        };
      case 'meetStory':
        return {
          'memory': currentMemory.copyWith(meetStory: extractedValue),
          'aiResponse': null,
        };
      default:
        return {'memory': currentMemory, 'aiResponse': null};
    }
  }

  /// Genera el prompt para procesar la respuesta del usuario
  static String _generateProcessingPrompt(
    final String userResponse,
    final MemoryData currentMemory,
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

  /// Formatea datos faltantes para procesamiento
  static String _formatMissingDataForProcessing(
    final List<String> missingData,
  ) {
    if (missingData.isEmpty) return 'TODOS LOS DATOS YA ESTÁN RECUPERADOS';

    final dataDescriptions = {
      'userName': 'Nombre del usuario (ej: Alberto, María, José)',
      'userCountry': 'País del usuario (ej: España, México, Francia)',
      'userBirthdate': 'Fecha nacimiento usuario (formato DD/MM/YYYY)',
      'aiCountry': 'País de la IA (ej: Japón, España, México)',
      'aiName': 'Nombre de la IA (ej: Yuna, Sakura, María)',
      'meetStory': 'Historia de cómo se conocieron o AUTO_GENERATE_STORY',
    };

    return missingData
        .map((final data) => '- ${dataDescriptions[data] ?? data}')
        .join('\n');
  }

  /// Formatea datos recordados para procesamiento
  static String _formatRememberedDataForProcessing(final MemoryData memory) {
    final remembered = <String>[];

    if (memory.userName != null && memory.userName!.isNotEmpty) {
      remembered.add('✓ Usuario: ${memory.userName}');
    }
    if (memory.userCountry != null && memory.userCountry!.isNotEmpty) {
      remembered.add('✓ País usuario: ${memory.userCountry}');
    }
    if (memory.userBirthdate != null && memory.userBirthdate!.isNotEmpty) {
      remembered.add('✓ Fecha nacimiento: ${memory.userBirthdate}');
    }
    if (memory.aiCountry != null && memory.aiCountry!.isNotEmpty) {
      remembered.add('✓ País IA: ${memory.aiCountry}');
    }
    if (memory.aiName != null && memory.aiName!.isNotEmpty) {
      remembered.add('✓ Nombre IA: ${memory.aiName}');
    }
    if (memory.meetStory != null && memory.meetStory!.isNotEmpty) {
      final story = memory.meetStory!.startsWith('GENERATED:')
          ? memory.meetStory!.substring('GENERATED:'.length)
          : memory.meetStory!;
      remembered.add(
        '✓ Historia: ${story.length > 50 ? "${story.substring(0, 50)}..." : story}',
      );
    }

    return remembered.isEmpty
        ? 'NINGÚN DATO RECUPERADO AÚN'
        : remembered.join('\n');
  }

  /// Crea un perfil básico para las operaciones de onboarding
  static AiChanProfile _createBasicProfile(
    final String userName,
    final String? aiName,
  ) {
    return AiChanProfile(
      userName: userName,
      userCountryCode: 'ES',
      userBirthdate: null,
      aiName: aiName ?? 'AI-chan',
      aiCountryCode: 'JP',
      aiBirthdate: null,
      biography: const {},
      appearance: const {},
      avatars: const [],
    );
  }

  static Future<dynamic> _sendAIRequest(
    final String prompt,
    final String userName,
    final Map<String, String> instructions,
    final List<Map<String, String>> conversationHistory,
    final dynamic aiProviderManager,
  ) async {
    final profile = _createBasicProfile(userName, null);

    final systemPrompt = SystemPrompt(
      profile: profile,
      dateTime: DateTime.now(),
      instructions: instructions,
    );

    // Crear el historial para el procesamiento incluyendo contexto de conversación
    final history = List<Map<String, String>>.from(conversationHistory);
    history.add({
      'role': 'system',
      'content': prompt,
      'datetime': DateTime.now().toIso8601String(),
    });

    // Use new AIProviderManager system
    final providerManager = aiProviderManager ?? AIProviderManager.instance;

    final response = await providerManager.sendMessage(
      history: history,
      systemPrompt: systemPrompt,
      capability: AICapability.textGeneration,
    );

    return response;
  }

  /// Crea una respuesta de error consistente para el nuevo formato
  static Map<String, dynamic> _createErrorResponse(
    final String? exception,
    final MemoryData currentMemory,
    final String userResponse,
  ) {
    return {
      'updatedMemory': currentMemory,
      'extractedData': {'type': null, 'value': null},
      'aiResponse': null,
      'error': true,
      'exception': exception,
    };
  }

  /// Helper method to build consistent process result responses
  static Map<String, dynamic> _buildProcessResult({
    required final MemoryData updatedMemory,
    required final Map<String, dynamic> extractedData,
    required final String? aiResponse,
    required final double confidence,
  }) {
    return {
      'updatedMemory': updatedMemory,
      'extractedData': extractedData,
      'aiResponse': aiResponse,
      'confidence': confidence,
      'error': false,
    };
  }
}
