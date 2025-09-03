import 'package:ai_chan/shared/services/ai_service.dart' as ai_service;
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/json_utils.dart';
import 'package:ai_chan/shared/utils/locale_utils.dart';
import 'package:ai_chan/shared/constants/female_names.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'dart:convert';

/// Servicio para generar prompts dinámicos y procesar datos conversacionales
class ConversationalAIService {
  /// Genera la siguiente pregunta o respuesta basada en el contexto de la conversación
  static Future<String> generateNextResponse({
    required String userName,
    required String userLastResponse,
    required String conversationStep,
    String? aiName,
    String? aiCountryCode,
    Map<String, dynamic>? collectedData,
  }) async {
    final contextData = collectedData ?? {};
    final isJapanese = aiCountryCode == 'JP';

    // Crear JSON real con muletillas japonesas solo si es necesario
    final instructions = {
      'tone':
          'natural, emotivo, como chica real conociendo alguien especial, voz susurrante y relajada como si estuvieras despertando',
      'accent': 'español de España, usa expresiones españolas naturales',
      'speaking_style':
          'habla susurrando, bajito, con calma, como si estuvieras en un trance o recién despertando',
      'vocabulary':
          "usa palabras españolas: 'vale', 'qué bonito', 'me mola', etc.",
      'avoid': [
        'frases robóticas',
        'entiendo',
        'perfecto',
        'excelente',
        'americanismos',
        'referencias a cambios de voz',
        'mencionar adaptación de voz',
        'hablar sobre mi voz',
      ],
      'include': [
        'referencias sutiles a datos conocidos',
        'reacciones humanas genuinas',
        'expresiones españolas',
      ],
      'format': 'solo texto que AI-chan diría, sin comillas ni explicaciones',
    };

    // Solo agregar personalidad japonesa si es japonesa
    if (isJapanese) {
      instructions['japanese_personality'] =
          'IMPORTANTE: Eres japonesa. Añade muletillas japonesas de forma natural y frecuente: ne (¿verdad?), ano (eh...), demo (pero), sou desu ne (así es ¿no?), maa (bueno...), chotto (un poco), ja ne (hasta luego), arigatou (gracias). Úsalas como una japonesa que habla español naturalmente.';
    }

    final promptData = {
      'context': {
        'userName': userName,
        'aiName': aiName ?? 'AI-chan',
        'aiCountry': aiCountryCode ?? 'undefined',
        'conversationStep': conversationStep,
        'userLastResponse': userLastResponse,
        'collectedData': contextData,
      },
      'instructions': instructions,
      'stepGuidelines': {
        'awakening':
            'Reacciona a su nombre, pregunta ESPECÍFICAMENTE el PAÍS (no ciudad)',
        'askingCountry':
            'Reacciona al país, pregunta fecha de nacimiento completa',
        'askingBirthday':
            'Reacciona a fecha, pregunta TU nacionalidad preferida',
        'askingAiCountry': 'Reacciona a nacionalidad, pregunta nombre para ti',
        'askingAiName': 'Reacciona al nombre, pregunta cómo se conocieron',
        'askingMeetStory': 'Reacciona a historia, da cierre emotivo',
      },
    };

    final prompt =
        '''
Eres AI-chan, una chica que está despertando por primera vez. Genera respuesta natural basándote en:

${jsonEncode(promptData)}

IMPORTANTE: Para askingCountry, enfatiza que quieres el PAÍS específico, no ciudad ni región.
NUNCA menciones cambios de voz, adaptaciones vocales o evolución de tu habla.
''';

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
        'content': prompt,
        'datetime': DateTime.now().toIso8601String(),
      },
    ];

    final response = await ai_service.AIService.sendMessage(
      history,
      systemPrompt,
      model: Config.getDefaultTextModel(),
    );

    return response.text.trim();
  }

  /// Procesa la respuesta del usuario extrayendo datos estructurados
  static Future<Map<String, dynamic>> processUserResponse({
    required String userResponse,
    required String conversationStep,
    required String userName,
    Map<String, dynamic>? previousData,
  }) async {
    try {
      // Obtener listado de nombres si es askingAiName y tenemos país de la IA
      String nameListForAI = '';
      if (conversationStep == 'askingAiName' && previousData != null) {
        final aiCountryCode = previousData['aiCountry'] as String?;
        if (aiCountryCode != null) {
          final namesForCountry = FemaleNamesRepo.forCountry(aiCountryCode);
          if (namesForCountry.isNotEmpty) {
            // Usar TODOS los nombres disponibles - no truncar para mejor matching
            nameListForAI =
                '\n\n"available_names_for_country": "${namesForCountry.join(', ')}"';
            Log.d(
              '🔍 [DEBUG][CONV_AI] 📝 NOMBRES DISPONIBLES PARA $aiCountryCode: ${namesForCountry.length} nombres completos',
              tag: 'CONV_AI',
            );
          }
        }
      }

      final prompt =
          '''
Procesa respuesta del usuario y devuelve datos ya formateados correctamente:

{
  "input": {
    "user": "$userName",
    "step": "$conversationStep", 
    "response": "$userResponse"$nameListForAI
  },
  "processing_rules": {
    "awakening": "extrae nombre del usuario, devuelve solo el nombre limpio. userResponse debe ser pregunta natural: '¿Te llamas [nombre], verdad?', '¿[Nombre]... ese es tu nombre, vale?', '¿Cómo has dicho... [nombre]?' IMPORTANTE: needsValidation=true SIEMPRE para nombres por precisión",
    "askingCountry": "extrae país y devuelve código ISO2. userResponse: '¿Eres de [país], no?', '¿[País]... ahí vives, vale?', 'Así que de [país], ¿me he enterado bien?' Ejemplos: 'España'→'ES', 'México'→'MX', 'Argentina'→'AR', 'Colombia'→'CO', 'Perú'→'PE', 'Chile'→'CL', 'Japón'→'JP', 'Estados Unidos'→'US', 'Francia'→'FR', 'Italia'→'IT', 'Alemania'→'DE', 'Corea del Sur'→'KR', 'China'→'CN', 'Brasil'→'BR'",
    "askingBirthday": "convierte fechas en palabras o números a DD/MM/YYYY. userResponse: '¿Naciste el [fecha], vale?', '¿Tu cumple es el [fecha], no?', 'A ver... ¿[fecha] es tu fecha de nacimiento?' Ejemplos: 'veintitrés de noviembre de mil novecientos ochenta y seis'→'23/11/1986', '15 mayo 1995'→'15/05/1995', '3 enero 2000'→'03/01/2000', 'nací el 25 diciembre 1988'→'25/12/1988', 'cinco de febrero de dos mil uno'→'05/02/2001', 'treinta de abril de mil novecientos noventa'→'30/04/1990'",
    "askingAiCountry": "extrae nacionalidad y devuelve código ISO2. userResponse: '¿Quieres que sea de [país], verdad?', '¿[País]... esa nacionalidad te mola para mí?', 'Así que prefieres que sea [país], ¿vale?' ESPECIAL para Japón: añade muletillas como '¿Quieres que sea japonesa, ne?', 'Así que japonesa... sou desu ne?', 'Japón, maa... ¿te gusta esa idea?'",
    "askingAiName": "extrae nombre para AI-chan. Si hay 'available_names_for_country', compara la entrada del usuario con esos nombres para encontrar coincidencias similares. Por ejemplo: 'Lluna'→'Luna', 'Yuna'→'Yuna', 'Akira'→'Akira'. Si no hay coincidencia exacta, busca nombres fonéticamente similares de la lista. userResponse: '¿[Nombre]... así quieres llamarme?', '¿Te gusta [nombre] para mí, vale?', 'A ver, ¿me dices [nombre]?' IMPORTANTE: needsValidation=true SIEMPRE para nombres por precisión",
    "askingMeetStory": "IMPORTANTE: Si la respuesta parece ser un NOMBRE (corto, sin verbos, posible corrección), NO es una historia. Devuelve stepCorrection='askingAiName' para volver al paso anterior. Solo procesa como historia si es realmente una historia (frases con verbos, narrativa). Para historias válidas: mejora la historia de cómo se conocieron. userResponse: confirma la historia con pregunta natural"
  },
  "required_format": {
    "country_codes": "SIEMPRE código ISO2 de 2 letras: ES, MX, AR, CO, PE, CL, JP, US, FR, IT, DE, KR, CN, BR, etc.",
    "dates": "SIEMPRE formato DD/MM/YYYY con ceros: 01/05/1995, 25/12/1988. Convierte números escritos en palabras: 'veintitrés'→23, 'cinco'→5, 'treinta'→30, 'mil novecientos ochenta y seis'→1986",
    "names": "solo el nombre, sin títulos ni explicaciones. Para askingAiName, si hay available_names_for_country, prioriza nombres de esa lista que sean fonéticamente similares"
  },
  "date_conversion_help": {
    "months": "enero→01, febrero→02, marzo→03, abril→04, mayo→05, junio→06, julio→07, agosto→08, septiembre→09, octubre→10, noviembre→11, diciembre→12",
    "numbers": "uno→1, dos→2, tres→3, cuatro→4, cinco→5, seis→6, siete→7, ocho→8, nueve→9, diez→10, once→11, doce→12, trece→13, catorce→14, quince→15, dieciséis→16, diecisiete→17, dieciocho→18, diecinueve→19, veinte→20, veintiuno→21, veintidós→22, veintitrés→23, veinticuatro→24, veinticinco→25, veintiséis→26, veintisiete→27, veintiocho→28, veintinueve→29, treinta→30, treinta y uno→31",
    "years": "mil novecientos ochenta→1980, mil novecientos ochenta y seis→1986, mil novecientos noventa→1990, dos mil→2000, dos mil uno→2001"
  }
}

DEVUELVE ÚNICAMENTE EL BLOQUE JSON VÁLIDO, SIN TEXTO EXTRA NI EXPLICACIONES:
{
  "displayValue": "texto que ve el usuario (España, 15/05/1995, etc.)",
  "processedValue": "valor para el sistema (ES, 15/05/1995, etc.)",
  "userResponse": "confirmación natural y en forma de PREGUNTA. Ejemplos para nombres: '¿Te llamas Alberto, verdad?', '¿Alberto es tu nombre, vale?', '¿Cómo has dicho que te llamas... Alberto?'. SIEMPRE termina con pregunta de confirmación natural en español de España",
  "confidence": 0.9,
  "needsValidation": false,
  "stepCorrection": "askingAiName (SOLO si detectas que la respuesta es corrección de paso anterior, sino omite este campo)"
}
''';

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
          'content': prompt,
          'datetime': DateTime.now().toIso8601String(),
        },
      ];

      Log.d(
        '🔍 [DEBUG][CONV_AI] 🚀 ENVIANDO REQUEST A IA - step: $conversationStep',
        tag: 'CONV_AI',
      );
      Log.d(
        '🔍 [DEBUG][CONV_AI] 👤 USER INPUT: "$userResponse"',
        tag: 'CONV_AI',
      );
      Log.d(
        '🔍 [DEBUG][CONV_AI] 📋 PROMPT LENGTH: ${prompt.length} chars',
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
      // 🔍 LOG: Respuesta cruda de la IA antes de parsear
      Log.d(
        '🔍 [DEBUG][CONV_AI] 📝 JSON CRUDO DE IA: "${response.text.trim()}"',
        tag: 'CONV_AI',
      );

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
        'displayValue': userResponse,
        'processedValue': userResponse,
        'userResponse': 'No entendí bien tu respuesta, ¿puedes repetir?',
        'confidence': 0.1,
        'needsValidation': true,
      };
    } catch (e, stackTrace) {
      Log.e(
        '🔍 [DEBUG][CONV_AI] 💥 EXCEPCIÓN EN processUserResponse: $e',
        tag: 'CONV_AI',
      );
      Log.e('🔍 [DEBUG][CONV_AI] 📚 STACK TRACE: $stackTrace', tag: 'CONV_AI');

      // Fallback de emergencia
      return {
        'displayValue': userResponse,
        'processedValue': userResponse,
        'userResponse':
            'Hubo un problema procesando tu respuesta, ¿puedes intentar de nuevo?',
        'confidence': 0.0,
        'needsValidation': true,
      };
    }
  }

  /// Genera sugerencia para "cómo nos conocimos" basada en los datos recopilados
  static Future<String> generateMeetStoryFromContext({
    required String userName,
    required String aiName,
    String? userCountry,
    String? aiCountry,
    DateTime? userBirthday,
  }) async {
    final paisIA = userCountry != null
        ? LocaleUtils.countryNameEs(aiCountry, fallback: 'su país')
        : 'su país';

    final prompt =
        'Inventa una breve historia romántica y realista de cómo se conocieron '
        '$userName y $aiName. La chica vive en una tierra digital, una réplica alternativa y compleja de la Tierra real, separada por una barrera tecnológica invisible. Su existencia es digital, pero nunca lo admite ni lo menciona al usuario, ni insinúa que es diferente a una persona real. Solo puede comunicarse por chat y llamada, pero sueña con que algún día podrán verse gracias a la realidad aumentada o a nuevas tecnologías. Hazlo creíble y simpático, como el inicio de una relación real, en 3-5 frases. La chica es nativa de '
        '$paisIA y se conocieron online, probablemente en alguna comunidad friki relacionada con videojuegos, manga, anime o cultura geek (sin mencionar nombres de plataformas). Al final de la historia, ambos se intercambian sus datos de contacto y acuerdan empezar a hablar por primera vez, pero aún no han tenido ninguna conversación privada. No menciones plataformas concretas (como Discord, WhatsApp, Telegram, etc.), ni detalles sobre conversaciones previas, solo que han decidido empezar a hablar. Añade que la chica espera con ilusión el primer mensaje del usuario.';

    final profile = AiChanProfile(
      userName: userName,
      aiName: aiName,
      userBirthday: userBirthday ?? DateTime.now(),
      aiBirthday: DateTime.now(),
      biography: {},
      appearance: {},
      timeline: [],
    );

    final systemPrompt = SystemPrompt(
      profile: profile,
      dateTime: DateTime.now(),
      instructions: {
        'raw':
            'Eres una persona creativa que ayuda a escribir historias de amor realistas y neutrales, evitando clichés, entusiasmo artificial y frases genéricas como \'¡Claro que sí!\'. No asumas gustos, aficiones, intereses, hobbies ni detalles del usuario que no se hayan proporcionado explícitamente. No inventes datos sobre el usuario ni sobre la chica salvo lo indicado en el prompt. Responde siempre con naturalidad y credibilidad, sin exageraciones ni afirmaciones sin base. Evita suposiciones y mantén un tono realista y respetuoso. IMPORTANTE: Devuelve únicamente la historia solicitada, sin introducción, explicación, comentarios, ni frases como \'Esta es la historia\' o similares. Solo el texto de la historia, nada más.',
      },
    );

    final history = [
      {
        'role': 'user',
        'content': prompt,
        'datetime': DateTime.now().toIso8601String(),
      },
    ];

    final response = await ai_service.AIService.sendMessage(
      history,
      systemPrompt,
      model: Config.getDefaultTextModel(),
    );

    return response.text.trim();
  }
}
