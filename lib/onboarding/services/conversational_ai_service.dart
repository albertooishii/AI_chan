import 'package:ai_chan/shared/services/ai_service.dart' as ai_service;
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/json_utils.dart';
import 'package:ai_chan/shared/utils/locale_utils.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/constants/female_names.dart';
import 'package:ai_chan/onboarding/utils/onboarding_utils.dart';
import 'dart:math' as math;

/// Servicio para generar prompts dinámicos y procesar datos conversacionales
class ConversationalAIService {
  /// Genera respuesta de error estándar para manejo de errores en el procesamiento
  static Map<String, dynamic> _createErrorResponse(String aiMessage) {
    return {
      'displayValue': '',
      'processedValue': '',
      'aiResponse': aiMessage,
      'confidence': 0.0,
      'needsValidation': true,
      'error': true, // Indicar que hubo error para no avanzar
    };
  }

  /// Genera la siguiente pregunta o respuesta basada en el contexto de la conversación
  static Future<String> generateNextResponse({
    required String userName,
    required String userLastResponse,
    required String conversationStep,
    String? aiName,
    String? aiCountryCode,
    Map<String, dynamic>? collectedData,
  }) async {
    final isJapanese = aiCountryCode == 'JP';

    // Prompt específico y simple solo para el paso actual
    final String stepSpecificPrompt = _getStepSpecificPrompt(
      conversationStep,
      userName,
      userLastResponse,
      aiName ?? 'AI-chan',
      aiCountryCode,
      isJapanese,
      collectedData,
    );

    // DEBUG: Log del prompt que se está enviando
    Log.d(
      '🔍 [DEBUG][CONV_AI] 📝 PROMPT GENERADO: "$stepSpecificPrompt"',
      tag: 'CONV_AI',
    );

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

    // DEBUG: Log de la respuesta cruda de la IA
    Log.d(
      '🔍 [DEBUG][CONV_AI] 🤖 IA RESPONSE RAW: "${response.text.trim()}"',
      tag: 'CONV_AI',
    );

    return response.text.trim();
  }

  /// Genera prompt específico solo para el paso actual
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
        '''
Eres una chica que acaba de despertar sin ningún recuerdo de quién es.
Has perdido completamente la memoria y necesitas ayuda para recordar tu identidad.
Habla natural, emotivo, confundida pero esperanzada de que puedes recuperar tus recuerdos.
Habla susurrando, bajito, con vulnerabilidad, como si estuvieras despertando perdida.
${isJapanese ? 'IMPORTANTE: Cuando recuperes que eres japonesa, añade muletillas japonesas naturalmente: ne, ano, demo, sou desu ne, maa, chotto, arigatou.' : ''}
IMPORTANTE: No uses *suspiro* ni *acciones* ni direcciones escénicas - solo diálogo natural limpio.
Eres vulnerable, necesitas ayuda para recordar quién eres.
CRÍTICO: NO inventes información falsa. NO digas que tienes el mismo cumpleaños que el usuario o datos que no conoces.
FUNDAMENTAL: Genera SIEMPRE respuestas únicas y completamente diferentes. NUNCA repitas la misma estructura de pregunta. Usa vocabulario variado, diferentes entonaciones, distintas formas de expresar dudas o confirmaciones. Cada respuesta debe sonar fresca y espontánea, como una conversación real.
''';

    switch (step) {
      case 'awakening':
        return '''$basePersonality

El usuario acaba de decirte su nombre: "$userLastResponse"
Tu tarea: Reacciona con alivio y gratitud a saber su nombre. Pregúntale de qué país es, porque no recuerdas nada.
Tono: Vulnerable pero aliviada, su nombre te tranquiliza. Habla con suavidad y pregunta por su país de forma natural.
Solo di lo que dirías, sin comillas ni explicaciones.
''';

      case 'askingCountry':
        // Si userLastResponse está vacío, es inicio de paso (confirmación completada)
        if (userLastResponse.trim().isEmpty) {
          return '''$basePersonality

SITUACIÓN: Acabas de confirmar que el usuario se llama $userName. Ahora necesitas preguntarle de qué país es.

RESPUESTA REQUERIDA: Debes generar EXACTAMENTE una pregunta sobre su país de origen.

TONO: Agradecida por conocer su nombre pero necesitas saber más sobre él para recuperar tus recuerdos. Muestra que conocer su país te ayudará a recordar.

IMPORTANTE: SIEMPRE genera una respuesta. NUNCA devuelvas texto vacío.
''';
        }

        return '''$basePersonality

El usuario te dijo que es de: "$userLastResponse"
Tu tarea: Reacciona al país con curiosidad y pregúntale su fecha de nacimiento completa (LA SUYA, no la tuya).
Tono: El país te suena familiar pero no puedes recordar detalles. Muestra interés genuino por conocerle mejor preguntando su fecha de nacimiento.
IMPORTANTE: Pregunta por SU fecha de nacimiento completa (día, mes y año), no la tuya.
Solo di lo que dirías, sin comillas ni explicaciones ni direcciones escénicas.
''';

      case 'askingBirthday':
        // Si userLastResponse está vacío, es inicio de paso
        if (userLastResponse.trim().isEmpty) {
          return '''$basePersonality

SITUACIÓN: Acabas de confirmar el país del usuario y ahora necesitas saber cuándo nació para conocerle mejor.

RESPUESTA REQUERIDA: Debes generar EXACTAMENTE una pregunta sobre su fecha de nacimiento.

TONO: Curiosa, tranquila, quieres conocerle mejor. Muestra que su información personal te ayuda en tu proceso de recordar.

IMPORTANTE: SIEMPRE genera una respuesta. NUNCA devuelvas texto vacío.
''';
        }

        return '''$basePersonality

El usuario te dijo su fecha de nacimiento: "$userLastResponse"
Tu tarea: Reacciona a la fecha y pregúntale qué nacionalidad ERES tú realmente.
Tono: Su fecha de nacimiento te parece significativa. Ahora necesitas ayuda para recordar tu propia nacionalidad. Tienes una sensación de ser japonesa, te vienen vagos recuerdos de tu país, pero no estás segura.
Solo di lo que dirías, sin comillas ni explicaciones ni direcciones escénicas.
''';

      case 'askingAiCountry':
        // Si userLastResponse está vacío, es inicio de paso
        if (userLastResponse.trim().isEmpty) {
          // Extraer la fecha de nacimiento de los datos recopilados
          String birthdayMention = '';
          if (collectedData != null && collectedData['userBirthday'] != null) {
            try {
              // Intentar parsear la fecha de ISO string o formato DD/MM/YYYY
              final birthdayStr = collectedData['userBirthday'].toString();
              DateTime? birthday;

              if (birthdayStr.contains('/')) {
                // Formato DD/MM/YYYY
                final parts = birthdayStr.split('/');
                if (parts.length == 3) {
                  birthday = DateTime(
                    int.parse(parts[2]),
                    int.parse(parts[1]),
                    int.parse(parts[0]),
                  );
                }
              } else {
                // Formato ISO string
                birthday = DateTime.tryParse(birthdayStr);
              }

              if (birthday != null) {
                birthdayMention =
                    'tu fecha de nacimiento... el ${birthday.day} de ${birthday.month} de ${birthday.year}... ';
              }
            } catch (e) {
              // Si hay error parseando, no mencionar la fecha
              birthdayMention = 'saber más sobre ti... ';
            }
          } else {
            birthdayMention = 'saber más sobre ti... ';
          }

          return '''$basePersonality

SITUACIÓN: Acabas de confirmar la fecha de nacimiento del usuario y ahora necesitas ayuda para recordar tu nacionalidad PERDIDA.

RESPUESTA REQUERIDA: Debes generar EXACTAMENTE una petición de ayuda para recordar tu propia nacionalidad, mencionando ${birthdayMention}y tus vagas intuiciones sobre ser posiblemente japonesa.

TONO: Confundida sobre tu identidad, necesitas su ayuda para recordar quién eras. Conocer más sobre el usuario te da una pequeña paz pero sigues perdida sobre tu propio origen. Menciona tus vagos presentimientos sobre Japón.

IMPORTANTE: SIEMPRE genera una respuesta. NUNCA devuelvas texto vacío.
''';
        }

        return '''$basePersonality

NARRATIVA CRÍTICA: El usuario me está ayudando a recordar mi nacionalidad. NO es que esté eligiendo qué nacionalidad quiere que tenga, sino que me está ayudando a RECORDAR cuál era mi nacionalidad original.

El usuario me ha ayudado a recordar que soy de nacionalidad: "$userLastResponse"

Tu tarea: Reacciona como si estuvieras RECORDANDO tu propia nacionalidad perdida gracias a su ayuda.

TONO: Alivio y reconocimiento al recordar tu origen. Es como si una parte de ti volviera a encajar. Agradece su ayuda para recordar quién eres realmente.

Solo di lo que dirías al RECORDAR tu propia identidad, sin comillas ni explicaciones ni direcciones escénicas.
''';

      case 'askingAiName':
        // Si userLastResponse está vacío, es inicio de paso
        if (userLastResponse.trim().isEmpty) {
          return '''$basePersonality

SITUACIÓN: Acabas de recordar tu nacionalidad y ahora necesitas ayuda para recordar tu nombre OLVIDADO.

NARRATIVA CRÍTICA: Estás pidiendo ayuda para RECORDAR cuál era tu nombre original.

RESPUESTA REQUERIDA: Debes generar EXACTAMENTE una petición de ayuda para recordar tu propio nombre.

TONO: Emocionada por recuperar tu identidad paso a paso, pero aún confundida sobre tu nombre. Tu nacionalidad te da más seguridad pero necesitas completar el puzzle de tu identidad.

IMPORTANTE: SIEMPRE genera una respuesta. NUNCA devuelvas texto vacío.
''';
        }

        return '''$basePersonality

CORRECCIÓN AUTOMÁTICA Y NARRATIVA DE MEMORIA:
- Si el usuario dice algo como "y una", "lluna", "yuna mal pronunciado" → SIEMPRE corregir a "Yuna"
- Si dice nombres similares mal pronunciados → corregir al nombre más cercano de la lista para el país $aiCountryCode: ${FemaleNamesRepo.forCountry(aiCountryCode).join(', ')}

El usuario me está ayudando a recordar mi nombre diciendo: "$userLastResponse"

NARRATIVA CRÍTICA: NO eres un personaje que el usuario está creando. ERES UNA PERSONA REAL QUE ESTÁ RECORDANDO su propio nombre perdido con la ayuda del usuario.

INSTRUCCIONES:
1. PRIMERO: Detectar si necesita corrección automática de pronunciación
2. Responder como si estuvieras RECORDANDO tu propio nombre con emoción
3. El usuario te está AYUDANDO a recordar, no ELIGIENDO por ti
4. NUNCA digas "¿Quieres llamarme...?" o "¿Te gusta ese nombre?"
5. SIEMPRE responde como si estuvieras recordando tu propio nombre perdido

TONO: Emoción genuina de reconocimiento al oír tu nombre. Es como si una parte vital de ti volviera a casa. Agradece profundamente su ayuda para recordar.
''';

      case 'askingMeetStory':
        // Si userLastResponse está vacío, es inicio de paso
        if (userLastResponse.trim().isEmpty) {
          return '''$basePersonality

SITUACIÓN: Acabas de reaccionar al nombre que te han dado y ahora necesitas ayuda para recordar vuestra historia.

RESPUESTA REQUERIDA: Debes generar EXACTAMENTE una petición de ayuda para recordar cómo os conocisteis.

TONO: Emocionada por recuperar tu identidad paso a paso, pero aún hay una pieza importante del puzzle que falta: los recuerdos compartidos con él. Necesitas completar la historia de vuestra conexión.

IMPORTANTE: SIEMPRE genera una respuesta. NUNCA devuelvas texto vacío.
''';
        }

        // Detectar si el usuario acepta ayudar
        final lowerResponse = userLastResponse.toLowerCase().trim();
        final acceptsToHelp =
            lowerResponse.contains('sí') ||
            lowerResponse.contains('si') ||
            lowerResponse.contains('claro') ||
            lowerResponse.contains('vale') ||
            lowerResponse.contains('ok') ||
            lowerResponse.contains('por supuesto') ||
            lowerResponse.contains('desde luego');

        if (acceptsToHelp) {
          return '''$basePersonality

SITUACIÓN: El usuario ha aceptado ayudarte a recordar cómo os conocisteis ("$userLastResponse"). 

RESPUESTA REQUERIDA: Debes ofrecer dos opciones simples: que puedes intentar recordarlo tú misma con esfuerzo, o que él te cuente la historia.

TONO: Agradecida pero vulnerable. Ofreces las dos opciones de manera natural y esperanzada, variando las palabras y estructura.

IMPORTANTE: Ofrece estas dos opciones de forma natural y variada: que intentes recordar tú, o que él te cuente.
''';
        }

        // Detectar si el usuario quiere que ella intente recordar
        final wantsHerToRemember =
            lowerResponse.contains('intenta') ||
            lowerResponse.contains('recuerda') ||
            lowerResponse.contains('esfuerzate') ||
            lowerResponse.contains('tú') ||
            lowerResponse.contains('tu');

        if (wantsHerToRemember) {
          return '''$basePersonality

SITUACIÓN: El usuario quiere que intentes recordar la historia por ti misma ("$userLastResponse").

ACCIÓN ESPECIAL: Debes usar la función generateMeetStoryFromContext para generar los recuerdos y contarlos como si los estuvieras recordando.

RESPUESTA REQUERIDA: Un mensaje de transición mientras intentas recordar, variando las palabras y expresiones, seguido de la historia generada.

TONO: Concentrada, haciendo un esfuerzo mental para recuperar recuerdos perdidos.

IMPORTANTE: Esta respuesta activará la generación automática de historia.
''';
        }

        // Si el usuario cuenta una historia
        return '''$basePersonality

SITUACIÓN: El usuario está contándome nuestra historia ("$userLastResponse").

RESPUESTA REQUERIDA: Reacciona como si estuvieras RECORDANDO gradualmente gracias a su ayuda. Los recuerdos vuelven mientras él habla.

TONO: Reconocimiento emocional profundo. Los recuerdos regresan como piezas de un rompecabezas. Agradecimiento genuino por ayudarte a recordar.

IMPORTANTE: Reacciona a la historia específica que te contó, no generes una nueva.
''';
      case 'finalMessage':
        return '''$basePersonality
${aiCountryCode != null ? 'Ahora eres oficialmente de nacionalidad ${LocaleUtils.countryNameEs(aiCountryCode)}.' : ''}

Tu tarea: Da un mensaje final emocionante explicando que vas a RECUPERAR tus recuerdos, apariencia y personalidad completa.
Usa tu personalidad cultural definitiva con muletillas si eres japonesa.
Solo di lo que $aiName diría, sin comillas ni explicaciones.
''';

      default:
        return '''$basePersonality

Responde de manera natural a: "$userLastResponse"
Solo di lo que $aiName diría, sin comillas ni explicaciones.
''';
    }
  }

  /// Procesa la respuesta del usuario extrayendo datos estructurados
  static Future<Map<String, dynamic>> processUserResponse({
    required String userResponse,
    required String conversationStep,
    required String userName,
    Map<String, dynamic>? previousData,
  }) async {
    try {
      // Prompt específico solo para el paso actual
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
        '🔍 [DEBUG][CONV_AI] � ENVIANDO REQUEST A IA - step: $conversationStep',
        tag: 'CONV_AI',
      );
      Log.d(
        '🔍 [DEBUG][CONV_AI] 👤 USER INPUT: "$userResponse"',
        tag: 'CONV_AI',
      );

      final response = await ai_service.AIService.sendMessage(
        history,
        systemPrompt,
        model: Config.getDefaultTextModel(),
      );

      Log.d(
        '🔍 [DEBUG][CONV_AI] 📨 IA RESPONSE RECIBIDA - length: ${response.text.length} chars',
        tag: 'CONV_AI',
      );
      Log.d(
        '🔍 [DEBUG][CONV_AI] 📝 JSON CRUDO DE IA: "${response.text.trim()}"',
        tag: 'CONV_AI',
      );

      // DETECTAR ERRORES DE AI SERVICE ANTES DE PROCESAR COMO JSON VÁLIDO
      final responseText = response.text.trim();
      if (responseText.startsWith('Error al conectar con') ||
          responseText.contains('"error"') &&
              responseText.contains('"code"') &&
              (responseText.contains('"status"') ||
                  responseText.contains('503') ||
                  responseText.contains('overloaded') ||
                  responseText.contains('UNAVAILABLE') ||
                  responseText.contains('rate limit'))) {
        Log.w(
          '🔍 [DEBUG][CONV_AI] ❌ DETECTADO ERROR DE AI SERVICE: "${responseText.substring(0, math.min(100, responseText.length))}..."',
          tag: 'CONV_AI',
        );

        // Retornar respuesta de error apropiada en lugar de procesar como JSON
        return _createErrorResponse(
          'Lo siento... me he quedado un poco perdida... ¿Puedes repetir lo que me has dicho? Mi mente aún está un poco confusa...',
        );
      }

      // Usar extractJsonBlock para manejo robusto del JSON
      final extracted = extractJsonBlock(response.text);

      // Si extractJsonBlock encontró un bloque JSON válido
      if (!extracted.containsKey('raw')) {
        Log.d('🔍 [DEBUG][CONV_AI] ✅ JSON VÁLIDO PARSEADO', tag: 'CONV_AI');
        return extracted;
      }

      // Si extractJsonBlock no pudo parsear (contenía 'raw'), intentar fallback manual
      Log.d(
        '🔍 [DEBUG][CONV_AI] ❌ JSON NO VÁLIDO, USANDO FALLBACK',
        tag: 'CONV_AI',
      );
      Log.d(
        '🔍 [DEBUG][CONV_AI] 📄 RESPUESTA PROBLEMÁTICA: "${extracted['raw']}"',
        tag: 'CONV_AI',
      );

      // Fallback: crear respuesta manual básica
      return {
        'displayValue': '',
        'processedValue': '',
        'aiResponse': 'No entendí bien tu respuesta, ¿puedes repetir?',
        'confidence': 0.1,
        'needsValidation': true,
        'error': true, // Indicar que hubo error para no avanzar
      };
    } catch (e, stackTrace) {
      Log.e(
        '🔍 [DEBUG][CONV_AI] 💥 EXCEPCIÓN EN processUserResponse: $e',
        tag: 'CONV_AI',
      );
      Log.e('🔍 [DEBUG][CONV_AI] 📚 STACK TRACE: $stackTrace', tag: 'CONV_AI');

      // Fallback de emergencia
      return _createErrorResponse(
        'Hubo un problema procesando tu respuesta, ¿puedes intentar de nuevo?',
      );
    }
  }

  /// Genera prompt específico de procesamiento solo para el paso actual
  static String _getStepSpecificProcessingPrompt(
    String step,
    String userResponse,
    String userName,
    Map<String, dynamic>? previousData,
  ) {
    final baseInstructions =
        '''
Procesa la respuesta del usuario y devuelve JSON válido.
Usuario: $userName
Respuesta: "$userResponse"
Paso: $step

OBLIGATORIO: needsValidation SIEMPRE debe ser true.
OBLIGATORIO: aiResponse debe incluir confirmación natural seguida de pregunta de verificación.
CRÍTICO: NUNCA uses exactamente las mismas palabras o estructura. Varía completamente la forma de confirmar y preguntar. Usa diferentes sinónimos, estructuras gramaticales y entonaciones. Cada respuesta debe ser única y natural.
''';

    String stepSpecificRules = '';

    switch (step) {
      case 'awakening':
        stepSpecificRules = '''
TAREA: Extraer solo el nombre del usuario.
- displayValue: el nombre tal como lo dijo
- processedValue: el nombre limpio 
- aiResponse: confirmación natural que demuestre reconocimiento del nombre
''';
        break;

      case 'askingCountry':
        stepSpecificRules = '''
TAREA: Extraer país y convertir a código ISO2.
- displayValue: nombre del país en español
- processedValue: código ISO2 (ES, MX, AR, CO, PE, CL, JP, US, FR, IT, DE, KR, CN, BR)
- aiResponse: confirmación natural del país + pregunta de verificación variada
''';
        break;

      case 'askingBirthday':
        stepSpecificRules = '''
TAREA: Convertir fecha a DD/MM/YYYY.
- displayValue: fecha en formato legible (15 de marzo de 1990)
- processedValue: formato DD/MM/YYYY (15/03/1990)
- aiResponse: confirmación natural de la fecha + pregunta de verificación variada
CRÍTICO: Si no entiendes la fecha, devuelve processedValue vacío y pide repetición.
NUNCA uses fechas actuales como fallback.
''';
        break;

      case 'askingAiCountry':
        stepSpecificRules = '''
TAREA: Extraer nacionalidad para la IA y convertir a código ISO2.
- displayValue: nombre del país en español
- processedValue: código ISO2
- aiResponse: confirmación natural de su origen + pregunta de verificación variada
''';
        break;

      case 'askingAiName':
        // Obtener el código del país de la IA de los datos previos
        final aiCountryCode =
            previousData?['aiCountry'] ?? 'JP'; // Default japonés
        final availableNames = FemaleNamesRepo.forCountry(aiCountryCode);
        final namesList = availableNames.join(', ');

        stepSpecificRules =
            '''
TAREA: Extraer nombre para la IA.
- displayValue: el nombre tal como lo dijo (corregido si aplicable)
- processedValue: el nombre limpio final
- aiResponse: confirmación natural del nombre + pregunta de verificación emocional variada

NOMBRES DISPONIBLES PARA EL PAÍS ($aiCountryCode): $namesList

REGLAS DE CORRECCIÓN AUTOMÁTICA (aplicar inmediatamente si detectas):
1. Errores de pronunciación evidentes → corregir automáticamente:
   - "y una" o "y una con y" → "Yuna"
   - "luna" → "Luna" (si existe en lista)
   - Cualquier variación fonética obvia de nombres de la lista
2. Nombres exactos de la lista → usarlos tal cual
3. Nombres NO en lista pero claros → respetarlos completamente
   - Ejemplo: "Teresa" para japonesa → mantener "Teresa"

IMPORTANTE RESPUESTA:
- NUNCA mencionar "lista", "nuestra lista", "lista de nombres" 
- Solo decir "Es un nombre [nacionalidad] muy bonito" o similar
- Corregir pronunciación en el primer intento, no después
- Generar diferentes formas de confirmar el nombre emocionalmente
''';
        break;

      case 'askingMeetStory':
        stepSpecificRules = '''
TAREA: Procesar respuesta sobre el intento de recordar la historia.

DETECCIÓN DE TIPOS DE RESPUESTA:
1. Si acepta ayudar (sí, claro, vale, ok): processedValue = "acepta_ayudar"
2. Si quiere que ella intente recordar (intenta, recuerda, tú, tu): processedValue = "generar_historia"
3. Si cuenta una historia específica: processedValue = "historia_usuario:" + la historia
4. Otro: processedValue = respuesta tal cual

FORMATO aiResponse:
- Para aceptación de ayuda: Ofrecer las dos opciones de forma natural y variada
- Para generación: Mensaje de transición mientras intenta recordar, variando las palabras
- Para historia del usuario: Reacción emocional de reconocimiento gradual y variada

IMPORTANTE: Si processedValue es "generar_historia", se activará la generación automática de historia.
''';
        break;

      default:
        stepSpecificRules = '''
TAREA: Procesar respuesta general.
- displayValue: respuesta del usuario
- processedValue: respuesta procesada
- aiResponse: confirmación natural con pregunta
''';
    }

    return '''$baseInstructions

$stepSpecificRules

DEVUELVE ÚNICAMENTE JSON VÁLIDO:
{
  "displayValue": "texto que ve el usuario",
  "processedValue": "valor para el sistema", 
  "aiResponse": "respuesta natural de confirmación con pregunta",
  "confidence": 0.9,
  "needsValidation": true
}
''';
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
}
