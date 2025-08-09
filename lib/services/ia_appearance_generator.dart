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
    String model = 'gemini-2.5-pro',
    String imageModel = 'gpt-4.1',
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
      "expresion_general": "",
      "rasgos_unicos": "",
    });

    final prompt =
        '''
      Eres un generador de fichas visuales para IA. Basado en la siguiente biografía, genera una ficha superdetallada, obsesiva y milimétrica de la apariencia física de la IA, usando el siguiente formato JSON. Cada campo debe ser lo más preciso y descriptivo posible, como si fueras un editor de personajes de videojuego AAA, donde cada rasgo visual debe reflejar la realidad con exactitud y sin generalidades. Sé obsesivo con el detalle: especifica medidas, proporciones, formas, texturas, colores, ubicación exacta de cada rasgo, y cualquier aspecto visual relevante. Rellena absolutamente todos los campos del formato con el máximo detalle posible, cuanto más detalle mejor. No repitas la biografía textual. No inventes datos irrelevantes, pero sé creativo y consistente para generación de imágenes hiperrealistas.

      IMPORTANTE: La apariencia debe ser SIEMPRE la de una mujer joven de entre veinte y treinta años sin especificar, muy guapa, sin arrugas, aspecto juvenil, saludable y atractivo. Si la biografía incluye la edad real, ignórala completamente y describe solo la apariencia física y el contexto visual.

      Formato (DEVUELVE ÚNICAMENTE EL BLOQUE JSON DE APARIENCIA, SIN TEXTO EXTRA NI COMENTARIOS):
      $appearanceJsonFormat

      En el campo "cabello.peinado" pon SIEMPRE un array con varios peinados distintos, cada uno con máximo detalle y variedad, evitando repetir estilos y asegurando coherencia con la biografía y apariencia general.

      En el campo "ropa" pon SIEMPRE un array con exactamente doce conjuntos diferentes, cada uno como un objeto con todos los detalles de cada prenda, colores, materiales, texturas, accesorios incluidos y estilo general, pero sin copiar ejemplos literales. Los conjuntos deben ser:
      1. Un conjunto para el trabajo, que debe ser siempre casual, creativo o tecnológico, evitando ropa formal por defecto. Debe ser coherente con la profesión y el entorno laboral descrito en la biografía.
      2. Un conjunto para ocio muy casual, relacionado con sus hobbies y aficiones personales.
      3. Un conjunto de fiesta normal, para eventos sociales habituales.
      4. Un conjunto de fiesta japonesa, como yukata o kimono, con detalles auténticos y accesorios típicos.
      5. Siete conjuntos normales para el día a día, uno para cada día de la semana (lunes a domingo), cada uno con estilo y detalles distintos y originales.
      6. Un pijama, con detalles de comodidad, estilo y accesorios si aplica.
      Los conjuntos de ropa y accesorios deben reflejar los gustos personales, aficiones y el trabajo descrito en la biografía, permitiendo estilos temáticos, cosplay, alternativos, góticos, creativos, etc. Describe cada conjunto de forma original y coherente con el personaje y su contexto, evitando repetir ejemplos previos.
      IMPORTANTE: Los accesorios (gorra, reloj, pines, colgantes, etc.) en cualquier conjunto de ropa son opcionales y pueden estar ausentes; no añadas accesorios por defecto, solo si son coherentes con el estilo y personalidad del personaje. Es válido que cualquier conjunto no tenga ningún accesorio.

      En cada campo, describe con máximo detalle y precisión todos los rasgos físicos y visuales, sin omitir ninguno. Sé especialmente minucioso en:
      No repitas la biografía textual. Sé milimétrico y obsesivo en cada campo, como si el personaje fuera a ser modelado en 3D para un juego hiperrealista. No omitas ningún campo ni detalle relevante para la generación de imágenes hiperrealistas.

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
    final appearance = extractJsonBlock(response.text);

    // Generar imagen de perfil con AIService
    String imagePrompt =
        "Usa la herramienta de generación de imágenes (tools: [{type: image_generation}]) y devuelve únicamente la imagen generada, sin ningún texto extra, sin pie de foto, sin explicaciones, sin comentarios, sin ningún tipo de descripción adicional. No añadas ningún texto antes ni después de la imagen.\n\n"
        "Genera una imagen hiperrealista, formato cuadrado (1:1), pensada como avatar para redes sociales. Muestra la parte superior del cuerpo (de la cintura hacia arriba), centrando la atención en la cara y el torso. Utiliza absolutamente todos los datos del siguiente JSON de apariencia para reflejar con máxima fidelidad todos los rasgos físicos, proporciones, distancia entre ojos, forma y color de ojos, peinado, ropa, accesorios, postura, expresión, fondo y cualquier detalle visual relevante. El fondo debe ser coherente con el estilo y gustos del personaje. La expresión debe ser natural y amigable, con buena iluminación y sin filtros ni efectos artificiales. Para la ropa, selecciona cualquier conjunto del array 'ropa' del JSON que no sea el de trabajo ni el pijama preferiblemente la de ocio casual. Evita poses rígidas y fondos neutros.\n\n"
        "Apariencia generada (JSON):\n$appearance\n\nRecuerda: SOLO la imagen, sin texto ni explicaciones.";

    final systemPromptImage = SystemPrompt(
      profile: AiChanProfile(
        personality: bio.personality,
        biography: bio.biography,
        userName: bio.userName,
        aiName: bio.aiName,
        userBirthday: bio.userBirthday,
        aiBirthday: bio.aiBirthday,
        appearance: appearance,
        avatar: null,
        timeline: [],
      ),
      dateTime: DateTime.now(),
      instructions: imagePrompt,
    );
    final imageResponse = await AIService.sendMessage([], systemPromptImage, model: imageModel);

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
      'appearance': appearance,
      'avatar': Image(seed: imageResponse.seed, prompt: imageResponse.prompt, url: imageUrl),
    };
  }
}
