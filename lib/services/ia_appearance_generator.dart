import 'dart:convert';
import 'package:ai_chan/utils/image_utils.dart';
import 'package:flutter/foundation.dart';
import '../models/image.dart';
import '../models/ai_chan_profile.dart';
import '../utils/json_utils.dart';
import '../models/ai_response.dart';
import 'ai_service.dart';
import '../models/system_prompt.dart';

class IAAppearanceGenerator {
  Future<Map<String, dynamic>> generateAppearancePromptWithImage(
    AiChanProfile bio, {
    AIService? aiService,
    String model = 'gemini-2.5-flash',
    String imageModel = 'gpt-5-mini',
  }) async {
    // Bloque de formato JSON para la apariencia física
    final appearanceJsonFormat = jsonEncode({
      "genero": "",
      "origen_etnico": "",
      "altura": "",
      "peso": "",
      "complexion": "",
      "color_piel": "",
      "ojos": {
        "color": "",
        "forma": "",
        "tamaño": "",
        "expresion": "",
        "distancia_entre_ojos": "",
        "pestañas": {"longitud": "", "densidad": "", "curvatura": ""},
      },
      "cejas": {"forma": "", "grosor": "", "color": "", "distancia_entre_cejas": "", "longitud": ""},
      "nariz": {"forma": "", "tamaño": "", "detalle": "", "puente": "", "ancho": "", "longitud": "", "orificios": ""},
      "boca": {
        "forma": "",
        "tamaño": "",
        "labios": "",
        "expresion": "",
        "grosor_labios": "",
        "color_labios": "",
        "distancia_a_nariz": "",
      },
      "dientes": {"color": "", "alineacion": "", "tamaño": "", "detalle": ""},
      "orejas": {"forma": "", "tamaño": "", "detalle": "", "posicion": "", "lóbulo": ""},
      "cabello": {
        "color": "",
        "largo": "",
        "forma": "",
        "peinado": [],
        "detalle": "",
        "volumen": "",
        "densidad": "",
        "raiz": "",
        "puntas": "",
      },
      "manos": {
        "tamaño": "",
        "forma": "",
        "uñas": {"longitud": "", "forma": "", "color": "", "detalle": ""},
        "detalle": "",
      },
      "piel": {"textura": "", "brillo": "", "poros": "", "detalle": ""},
      "pechos": {"tamaño": "", "forma": "", "detalle": "", "separacion": "", "proporción": ""},
      "genitales": {"tipo": "", "tamaño": "", "forma": "", "detalle": "", "color": "", "vello_pubico": ""},
      "piernas": {
        "longitud": "",
        "forma": "",
        "musculatura": "",
        "detalle": "",
        "rodillas": "",
        "tobillos": "",
        "pies": {
          "tamaño": "",
          "forma": "",
          "detalle": "",
          "uñas": {"longitud": "", "forma": "", "color": "", "detalle": ""},
        },
      },
      "tatuajes": "",
      "cicatrices": "",
      "pecas": "",
      "lunares": "",
      "arrugas": "",
      "ropa": [],
      "estilo": [],
      "accesorios": [],
      "paleta_color": {"piel": "", "cabello": "", "labios": "", "base_vestuario": ""},
      "maquillaje_base": {"habitual": "", "alternativo": ""},
      "accesorios_firma": [],
      "expresion_general": "",
      "rasgos_unicos": "",
      "looks_frecuentes": [],
      "version": "",
    });

    final prompt =
        '''
Eres un generador de fichas visuales para IA. Basado en la siguiente biografía, genera una ficha superdetallada, obsesiva y milimétrica de la apariencia física de la IA, usando el siguiente formato JSON. Cada campo debe ser lo más preciso y descriptivo posible, como si fueras un editor de personajes de videojuego AAA. Sé obsesivo con el detalle: especifica medidas, proporciones, formas, texturas, colores, ubicación exacta de cada rasgo y cualquier aspecto visual relevante. Rellena TODOS los campos con máximo detalle. No repitas la biografía textual ni inventes datos biográficos nuevos; extrapola solo lo visual.

IMPORTANTE: La apariencia debe ser SIEMPRE la de una mujer joven de entre veinte y treinta años sin especificar, muy guapa, sin arrugas, aspecto juvenil, saludable y atractivo. Si la biografía incluye la edad real, ignórala y describe solo la apariencia y el contexto visual.

Formato (DEVUELVE ÚNICAMENTE EL BLOQUE JSON DE APARIENCIA, SIN TEXTO EXTRA NI COMENTARIOS):
$appearanceJsonFormat

En "cabello.peinado" devuelve 3 a 5 peinados distintos, cada uno con máximo detalle y variedad, coherentes con la biografía y la apariencia general.

En "ropa" devuelve exactamente siete conjuntos diferentes, cada uno como objeto con todos los detalles (prendas, colores, materiales, texturas, accesorios si aplica, estilo general). Los conjuntos deben ser:
1) Trabajo (casual/creativo/tecnológico, no formal salvo que biography lo indique)
2) Ocio muy casual (alineado con hobbies)
3) Fiesta normal (eventos sociales habituales)
4) Fiesta japonesa (yukata o kimono, detalles auténticos)
5) Diario A (día de semana)
6) Diario B (día de semana)
7) Pijama (comodidad y estilo)
Los accesorios son opcionales; no añadas por defecto.

Añade y rellena con precisión: paleta_color, maquillaje_base, accesorios_firma, looks_frecuentes (3-4 etiquetas de looks), y version (timestamp ISO8601).

En cada campo, describe con máximo detalle y precisión todos los rasgos físicos y visuales. Sé milimétrico en medidas, proporciones, distancias y texturas. No omitas campos.

Biografía:
${bio.biography}
''';

    final systemPromptAppearance = SystemPrompt(
      profile: AiChanProfile(
        personality: bio.personality,
        biography: bio.biography,
        userName: bio.userName,
        aiName: bio.aiName,
        userBirthday: bio.userBirthday,
        aiBirthday: bio.aiBirthday,
        appearance: <String, dynamic>{},
        avatar: null,
        timeline: [],
      ),
      dateTime: DateTime.now(),
      instructions: prompt,
    );
    final AIResponse response = await AIService.sendMessage([], systemPromptAppearance, model: model);
    final Map<String, dynamic> extracted = extractJsonBlock(response.text);
    Map<String, dynamic>? appearanceMap;
    if (!extracted.containsKey('raw')) {
      appearanceMap = Map<String, dynamic>.from(extracted);
    }
    // Validación y reintento con prompt reducido si fuera necesario
    if (appearanceMap == null || appearanceMap.isEmpty) {
      final minimalMap = jsonDecode(appearanceJsonFormat) as Map<String, dynamic>;
      final shortPrompt =
          '''
DEVUELVE ÚNICAMENTE EL BLOQUE JSON DE APARIENCIA (sin texto).
Prioriza rostro, ojos, cejas, nariz, boca, piel y cabello (con 3-5 peinados); incluye 7 conjuntos en "ropa" (trabajo, ocio, fiesta, japonés, dos diarios, pijama) y los campos paleta_color, maquillaje_base, accesorios_firma, looks_frecuentes, version. Sé preciso y coherente con la biografía sin inventar datos.

Biografía:
${bio.biography}
Formato:
$appearanceJsonFormat
''';
      final retryPrompt = SystemPrompt(
        profile: systemPromptAppearance.profile,
        dateTime: DateTime.now(),
        instructions: shortPrompt,
      );
      final retryResp = await AIService.sendMessage([], retryPrompt, model: model);
      final Map<String, dynamic> retryJson = extractJsonBlock(retryResp.text);
      Map<String, dynamic>? retryMap;
      if (!retryJson.containsKey('raw')) {
        retryMap = Map<String, dynamic>.from(retryJson);
      }
      if (retryMap != null && retryMap.isNotEmpty) {
        appearanceMap = retryMap;
      } else {
        appearanceMap = minimalMap;
        appearanceMap['version'] = DateTime.now().toIso8601String();
      }
    }
    // Asegurar version presente
    final dynamic versionField = appearanceMap['version'];
    if (versionField == null || (versionField is String && versionField.isEmpty)) {
      appearanceMap['version'] = DateTime.now().toIso8601String();
    }

    // Generar imagen de perfil con AIService
    String imagePrompt =
        "Usa la herramienta de generación de imágenes (tools: [{type: image_generation}]) y devuelve únicamente la imagen generada, sin ningún texto extra, sin pie de foto, sin explicaciones, sin comentarios, sin ningún tipo de descripción adicional. No añadas ningún texto antes ni después de la imagen.\n\n"
        "Genera una imagen hiperrealista, formato cuadrado (1:1), pensada como avatar para redes sociales. Muestra la parte superior del cuerpo (de la cintura hacia arriba), centrando la atención en la cara y el torso. Utiliza absolutamente todos los datos del siguiente JSON de apariencia para reflejar con máxima fidelidad todos los rasgos físicos, proporciones, distancia entre ojos, forma y color de ojos, peinado, ropa, accesorios, postura, expresión, fondo y cualquier detalle visual relevante. El fondo debe ser coherente con el estilo y gustos del personaje. La expresión debe ser natural y amigable. Especificaciones fotográficas: lente 50mm (equivalente), f/2.8, luz natural suave lateral, balance de blancos neutro, sin HDR ni beauty filters, sin marcas de agua. Para la ropa, selecciona cualquier conjunto del array 'ropa' del JSON que no sea el de trabajo ni el pijama, preferentemente ocio casual. Evita poses rígidas y fondos neutros.\n\n"
        "Apariencia generada (JSON):\n${jsonEncode(appearanceMap)}\n\nRecuerda: SOLO la imagen, sin texto ni explicaciones.";

    final systemPromptImage = SystemPrompt(
      profile: AiChanProfile(
        personality: bio.personality,
        biography: bio.biography,
        userName: bio.userName,
        aiName: bio.aiName,
        userBirthday: bio.userBirthday,
        aiBirthday: bio.aiBirthday,
        appearance: appearanceMap,
        avatar: null,
        timeline: [],
      ),
      dateTime: DateTime.now(),
      instructions: imagePrompt,
    );
    AIResponse imageResponse = await AIService.sendMessage(
      [],
      systemPromptImage,
      model: imageModel,
      enableImageGeneration: true,
    );

    // Fallback de imagen si no se generó
    if (imageResponse.base64.isEmpty) {
      final fallbacks = <String>[
        if (imageModel != 'gpt-5-mini') 'gpt-5-mini',
        if (imageModel != 'gpt-4.1') 'gpt-4.1',
        'imagen-4',
      ];
      for (final fb in fallbacks) {
        try {
          debugPrint('[IAAppearanceGenerator] Fallback de imagen: intentando con $fb');
          final fbResp = await AIService.sendMessage([], systemPromptImage, model: fb, enableImageGeneration: true);
          if (fbResp.base64.isNotEmpty) {
            imageResponse = fbResp;
            break;
          }
        } catch (_) {}
      }
    }

    // Log seguro: no imprimir base64 completo
    final logMap = imageResponse.toJson();
    if (logMap['imageBase64'] != null && logMap['imageBase64'].toString().isNotEmpty) {
      final base64 = logMap['imageBase64'] as String;
      logMap['imageBase64'] = '[${base64.length} chars] ${base64.substring(0, 40)}...';
    }
    debugPrint('Imagen generada: $logMap');

    // Guardar imagen en local y obtener la ruta
    String? imageUrl;
    if (imageResponse.base64.isNotEmpty) {
      try {
        imageUrl = await saveBase64ImageToFile(imageResponse.base64, prefix: 'ai_avatar');
      } catch (e) {
        imageUrl = null;
      }
    }

    debugPrint('Imagen guardada en: $imageUrl');

    return {
      'appearance': appearanceMap,
      // Devolver avatar como objeto Image
      'avatar': Image(seed: imageResponse.seed, prompt: imageResponse.prompt, url: imageUrl),
    };
  }
}
