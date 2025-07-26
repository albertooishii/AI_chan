import 'dart:convert';
import 'package:ai_chan/utils/image_utils.dart';
import 'package:flutter/foundation.dart';
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
    String imageModel = 'gpt-4.1-mini',
  }) async {
    // Bloque de formato JSON para la apariencia física
    final appearanceJsonFormat = jsonEncode({
      "edad_aparente": "",
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

      IMPORTANTE: La edad_aparente debe ser SIEMPRE menor de 30 años, independientemente de la edad real o la fecha de nacimiento. La apariencia debe ser de una mujer muy guapa, con piel de porcelana, sin arrugas, aspecto juvenil, saludable y atractivo. Nunca pongas la edad real ni una edad superior a 29 en "edad_aparente". Si la biografía incluye la edad real, ignórala completamente y estima la edad visual solo según los rasgos físicos, estilo, postura y genética descritos. Justifica la juventud en la calidad de la piel, la ausencia de arrugas y el aspecto fresco y atractivo. Además, la edad_aparente debe ser siempre un número exacto (por ejemplo, "27"), nunca un rango ni texto ambiguo. Si tienes dudas, elige el valor más probable y natural según la descripción física y el contexto. ADVERTENCIA: Si la biografía incluye la edad real, nunca la pongas como edad_aparente. Elige una edad visual estimada que sea coherente con los rasgos físicos y el contexto, pero diferente a la edad real salvo que sea estrictamente necesario por la descripción física. Justifica tu elección en los rasgos visuales, no en la edad real.

      Formato (DEVUELVE ÚNICAMENTE EL BLOQUE JSON DE APARIENCIA, SIN TEXTO EXTRA NI COMENTARIOS):
      $appearanceJsonFormat

      En el campo "cabello.peinado" pon SIEMPRE un array con varios peinados distintos, cada uno con máximo detalle y variedad, evitando repetir estilos y asegurando coherencia con la biografía y apariencia general.

      En el campo "ropa" pon SIEMPRE un array con varios conjuntos diferentes, cada uno como un objeto con todos los detalles de cada prenda, colores, materiales, texturas, accesorios incluidos y estilo general, pero sin copiar ejemplos literales. Describe cada conjunto de forma original y coherente con el personaje, evitando repetir ejemplos previos.

      En cada campo, describe con máximo detalle y precisión todos los rasgos físicos y visuales, sin omitir ninguno. Sé especialmente minucioso en:
      No repitas la biografía textual. Sé milimétrico y obsesivo en cada campo, como si el personaje fuera a ser modelado en 3D para un juego hiperrealista. No omitas ningún campo ni detalle relevante para la generación de imágenes hiperrealistas.

      Biografía:
      ${bio.biography}
      ''';

    final systemPromptAppearance = SystemPrompt(
      profile: bio,
      dateTime: DateTime.now(),
      timeline: bio.timeline,
      recentMessages: [
        {"role": "user", "content": prompt, "datetime": DateTime.now().toIso8601String()},
      ],
      instructions: prompt,
    );
    final AIResponse response = await AIService.sendMessage([], systemPromptAppearance, model: model);
    final appearance = extractJsonBlock(response.text);

    // Generar imagen de perfil con AIService
    String imagePrompt =
        "Genera una imagen hiperrealista de medio cuerpo de la chica descrita en la siguiente apariencia JSON, con el máximo nivel de detalle y coherencia visual. La cara debe ser siempre la misma en todas las imágenes futuras. La imagen debe ser una foto de perfil CASUAL, como la que se usaría en Instagram o WhatsApp: actitud relajada, expresión natural y amigable, ligera sonrisa, fondo realista (por ejemplo, habitación luminosa, cafetería, parque, calle urbana, etc.), ropa casual y juvenil (nunca formal ni de oficina), buena iluminación, sin filtros ni efectos artificiales. Evita poses rígidas, ropa formal, fondos neutros o vacíos. La pose y la expresión deben ser naturales, espontáneas y variadas, evitando la rigidez y la simetría perfecta. La mirada puede ser directa a la cámara o variar de forma natural. Las manos y brazos deben estar en posiciones relajadas y cotidianas, transmitiendo cercanía y autenticidad, como una foto casual tomada con el móvil.\n\nApariencia generada (JSON):\n$appearance";

    final systemPromptImage = SystemPrompt(
      profile: bio,
      dateTime: DateTime.now(),
      timeline: bio.timeline,
      recentMessages: [
        {"role": "user", "content": imagePrompt, "datetime": DateTime.now().toIso8601String()},
      ],
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
    if (imageResponse.imageBase64.isNotEmpty) {
      try {
        imageUrl = await saveBase64ImageToFile(imageResponse.imageBase64, prefix: 'ai_avatar');
      } catch (e) {
        imageUrl = null;
      }
    }

    debugPrint('Imagen guardada en: $imageUrl');

    return {
      'appearance': appearance,
      'imageId': imageResponse.imageId,
      // 'imageBase64': imageResponse.imageBase64, // Solo resultado temporal, no guardar en perfil
      'imageUrl': imageUrl,
      'revisedPrompt': imageResponse.revisedPrompt,
    };
  }
}
