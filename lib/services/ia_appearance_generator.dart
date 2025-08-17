import 'package:flutter_dotenv/flutter_dotenv.dart';
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
  Future<Map<String, dynamic>> generateAppearancePromptWithImage(AiChanProfile bio, {AIService? aiService}) async {
    final usedModel = dotenv.env['DEFAULT_TEXT_MODEL'] ?? '';
    final imageModel = dotenv.env['DEFAULT_IMAGE_MODEL'] ?? '';

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
    });

    final prompt =
        '''
Eres un generador de fichas visuales para IA. Basado en la siguiente biografía, genera una ficha superdetallada, obsesiva y milimétrica de la apariencia física de la IA, usando el siguiente formato JSON. Cada campo debe ser lo más preciso y descriptivo posible, como si fueras un editor de personajes de videojuego AAA. Sé obsesivo con el detalle: especifica medidas, proporciones, formas, texturas, colores, ubicación exacta de cada rasgo y cualquier aspecto visual relevante. Rellena TODOS los campos con máximo detalle. No repitas la biografía textual ni inventes datos biográficos nuevos; extrapola solo lo visual.

IMPORTANTE: La apariencia debe ser SIEMPRE la de una mujer joven de unos 25 años años aunque realmente tenga otra edad, muy guapa, sin arrugas, aspecto juvenil, saludable y atractivo. Si la biografía incluye la edad real o la fecha de nacimiento, ignóralas y describe solo la apariencia y el contexto visual.

Formato (DEVUELVE ÚNICAMENTE EL BLOQUE JSON DE APARIENCIA, SIN TEXTO EXTRA NI COMENTARIOS):
$appearanceJsonFormat

En "cabello.peinado" devuelve 3 a 5 peinados distintos, cada uno con máximo detalle y variedad, coherentes con la biografía y la apariencia general.

En "ropa" devuelve exactamente nueve conjuntos diferentes, cada uno como objeto con todos los detalles (prendas, colores, materiales, texturas, accesorios si aplica, estilo general). Los conjuntos deben ser:
1) Trabajo (casual/creativo/tecnológico, no formal salvo que biography lo indique)
2) Ocio muy casual (alineado con hobbies)
3) Fiesta normal (eventos sociales habituales)
4) Fiesta o evento cultural del país de origen (atuendo tradicional auténtico y respetuoso, acorde a la biografía; si la biografía es japonesa, usa yukata o kimono; si es de otro país, usa la prenda tradicional o look festivo local adecuado. Si no hay datos culturales, usa un outfit de evento elegante local contemporáneo, no tradicional.)
5) Diario primavera (día de semana, clima templado)
6) Diario verano (día de semana, clima cálido)
7) Diario otoño (día de semana, clima templado/fresco)
8) Diario invierno (día de semana, clima frío)
9) Pijama (comodidad y estilo)
Los accesorios son opcionales; no añadas por defecto.

// Conjuntos de diario fijos por estación (primavera, verano, otoño, invierno); no adaptar por fecha actual.

En cada campo, describe con máximo detalle y precisión todos los rasgos físicos y visuales. Sé milimétrico en medidas, proporciones, distancias y texturas. No omitas campos.

Biografía:
${bio.biography}
''';

    final systemPromptAppearance = SystemPrompt(
      profile: AiChanProfile(
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
      instructions: {'raw': prompt},
    );
    // Reintentos con el mismo prompt/modelo para obtener JSON válido
    debugPrint('[IAAppearanceGenerator] Apariencia: intentos JSON (max=3) con modelo $usedModel');
    const int maxJsonAttempts = 3;
    Map<String, dynamic>? appearanceMap;
    for (int attempt = 0; attempt < maxJsonAttempts; attempt++) {
      debugPrint('[IAAppearanceGenerator] Apariencia: intento ${attempt + 1}/$maxJsonAttempts (modelo=$usedModel)');
      try {
        final AIResponse resp = await AIService.sendMessage([], systemPromptAppearance, model: usedModel);
        if ((resp.text).trim().isEmpty) {
          debugPrint('[IAAppearanceGenerator] Apariencia: respuesta vacía (posible desconexión), reintentando…');
          continue;
        }
        final Map<String, dynamic> extracted = extractJsonBlock(resp.text);
        if (!extracted.containsKey('raw')) {
          appearanceMap = Map<String, dynamic>.from(extracted);
          debugPrint(
            '[IAAppearanceGenerator] Apariencia: JSON OK en intento ${attempt + 1} (keys=${appearanceMap.keys.length})',
          );
          break;
        }
        debugPrint('[IAAppearanceGenerator] Apariencia: intento ${attempt + 1} sin JSON válido, reintentando…');
      } catch (err) {
        debugPrint('[IAAppearanceGenerator] Apariencia: error de red/timeout en intento ${attempt + 1}: $err');
      }
    }
    // Si tras los intentos no hay JSON válido, cancelar sin fallback
    if (appearanceMap == null || appearanceMap.isEmpty) {
      throw Exception('No se pudo generar la apariencia en formato JSON válido.');
    }
    // Sin campo de versión: no se requiere completar timestamp

    // Generar imagen de perfil con AIService
    String imagePrompt =
        "Usa la herramienta de generación de imágenes (tools: [{type: image_generation}]) y devuelve únicamente la imagen generada, sin ningún texto extra, sin pie de foto, sin explicaciones, sin comentarios, sin ningún tipo de descripción adicional. No añadas ningún texto antes ni después de la imagen.\n\n"
        "Genera una imagen hiperrealista en formato cuadrado (1:1) con encuadre limpio y recortado (sin cortar cabeza, frente, barbilla ni hombros principales), pensada como avatar para redes sociales. Muestra la parte superior del cuerpo (de la cintura hacia arriba), centrando la atención en la cara y el torso. La apariencia DEBE reflejar claramente a una mujer joven de unos 25 años (aspecto juvenil, saludable, sin arrugas marcadas), independientemente de edades reales o fechas mencionadas en la biografía. Utiliza todos los datos del JSON de apariencia para reflejar rasgos físicos, proporciones, ojos, peinado, ropa, accesorios, postura, expresión, fondo y detalles relevantes. El fondo debe ser coherente con su estilo y gustos y la expresión natural y cercana. Para la ropa, elige uno de los conjuntos existentes en el array 'ropa' (que no sea el de trabajo ni el pijama). No inventes ni mezcles prendas nuevas: usa el conjunto exactamente como está descrito en el JSON. Evita poses rígidas y fondos totalmente planos.\n\nAñade un toque divertido y espontáneo coherente con los intereses/hobbies mencionados en la biografía (por ejemplo un gesto, una micro‑expresión, la interacción casual con un objeto del fondo o un detalle ambiental), siempre sutil y natural, sin introducir texto, logos, marcas ni elementos que contradigan el JSON y sin añadir prendas o accesorios no listados. El resultado debe transmitir cercanía, energía positiva y personalidad propia sin volverse caricatura.\n\n"
        "Apariencia generada (JSON):\n${jsonEncode(appearanceMap)}\n\nRecuerda: SOLO la imagen, sin texto ni explicaciones.";

    final systemPromptImage = SystemPrompt(
      profile: AiChanProfile(
        biography: bio.biography,
        userName: bio.userName,
        aiName: bio.aiName,
        userBirthday: null,
        aiBirthday: null,
        appearance: appearanceMap,
        avatar: null,
        timeline: [],
      ),
      dateTime: DateTime.now(),
      instructions: {'raw': imagePrompt},
    );

    final String forcedImageModel = dotenv.env['DEFAULT_IMAGE_MODEL'] ?? '';
    if (imageModel != forcedImageModel) {
      debugPrint('[IAAppearanceGenerator] Avatar: imageModel "$imageModel" ignorado; se fuerza "$forcedImageModel"');
    }
    debugPrint('[IAAppearanceGenerator] Avatar: generando imagen con modelo $forcedImageModel (intentos por modelo=3)');
    AIResponse imageResponse = AIResponse(text: '', base64: '', seed: '', prompt: '');
    const int maxImageAttemptsPerModel = 3;
    for (int attempt = 0; attempt < maxImageAttemptsPerModel; attempt++) {
      debugPrint(
        '[IAAppearanceGenerator] Avatar: intento ${attempt + 1}/$maxImageAttemptsPerModel con $forcedImageModel',
      );
      try {
        final resp = await AIService.sendMessage(
          [],
          systemPromptImage,
          model: forcedImageModel,
          enableImageGeneration: true,
        );
        if (resp.base64.isNotEmpty) {
          imageResponse = resp;
          debugPrint('[IAAppearanceGenerator] Avatar: imagen obtenida con $forcedImageModel en intento ${attempt + 1}');
          break;
        }
        debugPrint('[IAAppearanceGenerator] Avatar: intento ${attempt + 1} sin imagen');
      } catch (err) {
        debugPrint('[IAAppearanceGenerator] Avatar: error de red/timeout en intento ${attempt + 1}: $err');
      }
    }

    // Si no se generó imagen tras los reintentos, lanzar excepción para que la UI pregunte al usuario.
    if (imageResponse.base64.isEmpty) {
      throw Exception('No se pudo generar el avatar tras $maxImageAttemptsPerModel intentos con $forcedImageModel.');
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
    try {
      imageUrl = await saveBase64ImageToFile(imageResponse.base64, prefix: 'ai_avatar');
    } catch (e) {
      imageUrl = null;
    }

    if (imageUrl == null || imageUrl.isEmpty) {
      throw Exception('Se generó el avatar pero no se pudo guardar la imagen en el dispositivo.');
    }

    debugPrint('Imagen guardada en: $imageUrl');

    return {
      'appearance': appearanceMap,
      // Devolver avatar como objeto Image (nunca null)
      'avatar': Image(seed: imageResponse.seed, prompt: imageResponse.prompt, url: imageUrl),
    };
  }
}
