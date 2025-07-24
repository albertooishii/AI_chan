import 'dart:convert';
import '../models/ai_chan_profile.dart';
import '../utils/json_utils.dart';
import '../models/ai_response.dart';
import 'ai_service.dart';

class IAAppearanceGenerator {
  Future<Map<String, dynamic>> generateAppearancePrompt(
    AiChanProfile bio, {
    AIService? aiService,
    String model = 'gemini-2.5-flash',
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

      En el campo "cabello.peinado" pon SIEMPRE un array con varios peinados distintos, cada uno con máximo detalle (ejemplo: ["coleta alta con mechones sueltos y textura sedosa", "trenza lateral con volumen y puntas onduladas", "melena suelta con raya al medio y ondas naturales"]).

      En el campo "ropa" pon SIEMPRE un array con varios conjuntos diferentes, cada uno como un objeto con todos los detalles de cada prenda, colores, materiales, texturas, accesorios incluidos, y estilo general. Ejemplo:
      "ropa": [
        {
          "nombre": "Conjunto casual elegante",
          "prendas": [
            {"tipo": "blusa", "color": "blanco perla", "material": "seda", "detalle": "mangas abullonadas, cuello en V"},
            {"tipo": "falda", "color": "azul marino", "material": "algodón", "detalle": "corte recto, largo hasta la rodilla"}
          ],
          "accesorios": ["pendientes de plata", "reloj dorado"],
          "calzado": {"tipo": "zapatos de tacón", "color": "beige", "material": "cuero"},
          "estilo": "sofisticado, juvenil"
        },
        ...
      ]

      En cada campo, describe con máximo detalle y precisión todos los rasgos físicos y visuales, sin omitir ninguno. Sé especialmente minucioso en:
      No repitas la biografía textual. Sé milimétrico y obsesivo en cada campo, como si el personaje fuera a ser modelado en 3D para un juego hiperrealista. No omitas ningún campo ni detalle relevante para la generación de imágenes hiperrealistas.

      Biografía:
      ${bio.toJson()}
      ''';

    final AIResponse response = await AIService.sendMessage(
      [
        {"role": "user", "content": prompt},
      ],
      '',
      model: model,
    );
    final appearance = extractJsonBlock(response.text);

    return appearance;
  }
}
