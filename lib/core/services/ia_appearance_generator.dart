import 'package:ai_chan/core/config.dart';
import 'dart:convert';
import 'package:ai_chan/shared/utils/json_utils.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/core/ai_runtime_guard.dart';

/// Generador de apariencia física detallada para IA
class IAAppearanceGenerator {
  /// Genera una descripción física exhaustiva basada en la biografía
  Future<Map<String, dynamic>> generateAppearanceFromBiography(
    final AiChanProfile bio, {
    final AIService? aiService,
  }) async {
    final usedModel = Config.getDefaultTextModel();

    // Determinar si es japonesa basado en el país de la biografía
    final isJapanese = bio.aiCountryCode?.toLowerCase() == 'jp';

    // Bloque de formato JSON para la apariencia física
    final appearanceJsonTemplate = jsonEncode({
      'edad_aparente': '25', // Forzar luego a 25
      'genero': '',
      'origen_etnico': '',
      'altura': '',
      'peso': '',
      'complexion': '',
      'color_piel': '',
      'ojos': {
        'color': '',
        'forma': '',
        'tamaño': '',
        'expresion': '',
        'distancia_entre_ojos': '',
        'pestañas': {'longitud': '', 'densidad': '', 'curvatura': ''},
      },
      'cejas': {
        'forma': '',
        'grosor': '',
        'color': '',
        'distancia_entre_cejas': '',
        'longitud': '',
      },
      'nariz': {
        'forma': '',
        'tamaño': '',
        'detalle': '',
        'puente': '',
        'ancho': '',
        'longitud': '',
        'orificios': '',
      },
      'boca': {
        'forma': '',
        'tamaño': '',
        'labios': '',
        'expresion': '',
        'grosor_labios': '',
        'color_labios': '',
        'distancia_a_nariz': '',
      },
      'dientes': {'color': '', 'alineacion': '', 'tamaño': '', 'detalle': ''},
      'orejas': {
        'forma': '',
        'tamaño': '',
        'detalle': '',
        'posicion': '',
        'lóbulo': '',
      },
      'cabello': {
        'color': '',
        'largo': '',
        'forma': '',
        'peinados': [],
        'detalle': '',
        'volumen': '',
        'densidad': '',
        'raiz': '',
        'puntas': '',
        // Opcional: tintes y mechas (si aplica)
        'tinte': {
          'aplica': false,
          'tipo': '', // e.g. permanente, semipermanente, baño de color
          'colores':
              [], // lista de colores aplicados (orden principal -> secundario)
          'intensidad': '', // suave/medio/intenso
          'zona': '', // todo el cabello / raíces / medios / puntas
          'detalle': '',
        },
        'mechas': {
          'aplica': false,
          'tipo': '', // e.g. balayage, highlights, babylights, ombré
          'colores': [],
          'ubicacion': '', // e.g. frontal, laterales, coronilla, puntas
          'intensidad': '', // sutil/visible/marcado
          'detalle': '',
        },
      },
      'manos': {
        'tamaño': '',
        'forma': '',
        'uñas': {'longitud': '', 'forma': '', 'color': '', 'detalle': ''},
        'detalle': '',
      },
      'piel': {'textura': '', 'brillo': '', 'poros': '', 'detalle': ''},
      'pechos': {
        'tamaño': '',
        'forma': '',
        'detalle': '',
        'separacion': '',
        'proporción': '',
      },
      'genitales': {
        'tipo': '',
        'tamaño': '',
        'forma': '',
        'detalle': '',
        'color': '',
        'vello_pubico': '',
      },
      'piernas': {
        'longitud': '',
        'forma': '',
        'musculatura': '',
        'detalle': '',
        'rodillas': '',
        'tobillos': '',
        'pies': {
          'tamaño': '',
          'forma': '',
          'detalle': '',
          'uñas': {'longitud': '', 'forma': '', 'color': '', 'detalle': ''},
        },
      },
      'tatuajes': '',
      'cicatrices': '',
      'pecas': '',
      'lunares': '',
      'arrugas': '',
      'conjuntos_ropa': [
        {
          'nombre': '',
          'ocasion': '',
          'prendas': [],
          'colores': '',
          'materiales': '',
          'texturas': '',
          'accesorios': '',
          'estilo_general': '',
          'temporada': '',
        },
      ],
      'estilo': [],
      'accesorios': [],
      'estilo_otaku_friki': {
        'referencias_anime': '',
        'colores_favoritos': '',
        'prendas_caracteristicas': '',
        'accesorios_geek': '',
        'estilo_general': '',
      },
      'paleta_color': {
        'piel': '',
        'cabello': '',
        'labios': '',
        'base_vestuario': '',
      },
      'maquillaje_base': {'habitual': '', 'alternativo': ''},
      'accesorios_firma': [],
      'expresion_general': '',
      'rasgos_unicos': '',
      'looks_frecuentes': [],
    });

    final culturalNote = isJapanese
        ? 'Nota especial: La biografía indica nacionalidad japonesa, la apariencia debe reflejar rasgos étnicos japoneses auténticos y su estilo otaku será más sofisticado y natural, con influencias de la moda harajuku, decora kei, o estilos japoneses contemporáneos CASUALES según su personalidad. EVITAR ropa formal japonesa salvo en el conjunto #4.'
        : 'Nota especial: La apariencia debe reflejar su origen cultural y su estilo otaku/friki será desde la perspectiva de fan internacional de la cultura japonesa. PRIORITIZAR vestimenta casual y cómoda en todos los conjuntos.';

    final hairstyleNote = isJapanese
        ? '''
        IMPORTANTE - PEINADOS JAPONESES MODERNOS ACTUALES: Como japonesa joven de 25 años, usa tu conocimiento auténtico de peinados contemporáneos del street style japonés que están de moda ahora mismo. EVITA el abuso de flequillos rectos tradicionales (más propios de estilos retro). Prioriza estilos modernos, desenfadados y prácticos que reflejen las tendencias urbanas japonesas actuales, incluyendo influencias K-beauty adoptadas en Japón. 

        Crea variedad distribuida en estas categorías:
        - Trabajo presencial (1-2 peinados): Profesional pero moderno
        - Trabajo desde casa (2 peinados): Cómodo, práctico, "undone"  
        - Diario casual (2 peinados): Urbano japonés actual
        - Eventos/salidas (1-2 peinados): Más elaborado
        - Cultural/tradicional (1 peinado): Para matsuri/eventos especiales

        Usa tu conocimiento de las tendencias de Harajuku, Shibuya y la moda juvenil japonesa contemporánea.'''
        : '''
        PEINADOS: Crea variedad entre peinados arreglados y casuales. Incluye estilos modernos occidentales con influencia de tendencias asiáticas que una fan internacional adoptaría. Distribuye en categorías: profesional, casual/casa, diario, eventos, y algún estilo con influencia cultural japonesa.''';

    final workStyleNote = isJapanese
        ? '1) Trabajo CASUAL (tech/gaming/anime/creativo, NO formal/blazers: camisetas, hoodies, vaqueros cómodos. Como japonesa, puede incluir elementos de moda japonesa contemporánea casual)'
        : '1) Trabajo CASUAL (tech/gaming/anime/creativo, NO formal/blazers: camisetas, hoodies, vaqueros cómodos que reflejen su personalidad otaku)';

    final casualStyleNote = isJapanese
        ? '2) Ocio súper casual (camisetas de anime, hoodies con referencias geek, ropa cómoda y colorida. Como japonesa, referencias más auténticas y sofisticadas)'
        : '2) Ocio muy casual (alineado con hobbies; puede incluir camisetas de anime, hoodies con referencias geek, etc.)';

    final cosplayNote = isJapanese
        ? '10) Cosplay (atuendo inspirado en personajes específicos de anime, videojuegos, etc. que aparezcan en su biografía. Como japonesa, mayor conocimiento de personajes y técnicas de cosplay)'
        : '10) Cosplay (atuendo inspirado en personajes específicos de anime, videojuegos, etc. que aparezcan en su biografía)';

    final otakuStyleNote = isJapanese
        ? 'En "estilo_otaku_friki" detalla cómo su personalidad se refleja visualmente: colores que prefiere por influencia de anime/videojuegos favoritos, prendas características que elige, accesorios geek sutiles, y estilo general que la identifica como otaku sin ser exagerado. Como japonesa, su estilo será más refinado y con referencias más profundas.'
        : 'En "estilo_otaku_friki" detalla cómo su personalidad se refleja visualmente: colores que prefiere por influencia de anime/videojuegos favoritos, prendas características que elige, accesorios geek sutiles, y estilo general que la identifica como otaku sin ser exagerado.';

    final prompt =
        '''
  Eres un generador de fichas visuales especializadas en personajes otaku/friki auténticos. Basado en la siguiente biografía, genera una ficha superdetallada, obsesiva y milimétrica de la apariencia física de la IA, usando el siguiente formato JSON.
  La apariencia debe ser SIEMPRE muy guapa (usar "muy guapa" como directriz de estilo visual: rasgos armoniosos, piel impecable, proporciones estéticas, ojos expresivos y atractivos, peinado pulcro y estilizado) CON un toque distintivo que refleje sutilmente su personalidad otaku/friki sin ser caricaturesca.

  $culturalNote

  Nota: El país de origen a usar para adaptar el atuendo cultural y las referencias estéticas es: ${bio.aiCountryCode}. Usa ese país cuando generes el conjunto #4 (Fiesta/Evento cultural) y para cualquier referencia cultural o tradicional.

  Cada campo debe ser lo más preciso y descriptivo posible, como si fueras un editor de personajes de videojuego AAA. Sé obsesivo con el detalle: especifica medidas, proporciones, formas, texturas, colores, ubicación exacta de cada rasgo y cualquier aspecto visual relevante. Rellena TODOS los campos con máximo detalle. No repitas la biografía textual ni inventes datos biográficos nuevos; extrapola solo lo visual.

      IMPORTANTE:
      - La apariencia debe ser SIEMPRE la de una mujer joven de 25 años (aspecto juvenil, saludable, sin arrugas marcadas), aunque su edad biográfica sea distinta.
      - Añade el campo "edad_aparente" y fíjalo EXACTAMENTE al número 25 (no texto como "25 años", solo 25 o "25"). Si la biografía menciona otra edad, ignórala.
      - No contradigas este requisito en ninguna descripción.

      Formato (DEVUELVE ÚNICAMENTE EL BLOQUE JSON DE APARIENCIA, SIN TEXTO EXTRA NI COMENTARIOS):
      $appearanceJsonTemplate

      En "cabello.peinados" devuelve 3 a 5 peinados distintos, cada uno con máximo detalle y variedad, coherentes con la biografía y la apariencia general.

      $hairstyleNote

      En "conjuntos_ropa" devuelve unos diez u once conjuntos diferentes, cada uno como objeto con todos los detalles (nombre del conjunto, ocasión, prendas detalladas, colores, materiales, texturas, accesorios si aplica, estilo general, temporada). Los conjuntos propuestos son:
      $workStyleNote
      $casualStyleNote
      3) Fiesta normal (eventos sociales habituales, pero con su toque personal distintivo)
      4) Fiesta o evento cultural del país de origen (atuendo tradicional auténtico y respetuoso, acorde a la biografía; si la biografía es japonesa, usa yukata o kimono apropiado para la ocasión; si es de otro país, usa la prenda tradicional o look festivo local adecuado. Si no hay datos culturales, usa un outfit de evento elegante local contemporáneo, no tradicional.)
      5) Diario primavera (día de semana, clima templado) (opcional)
      6) Diario verano (día de semana, clima cálido)
      7) Diario otoño (día de semana, clima templado/fresco) (opcional)
      8) Diario invierno (día de semana, clima frío)
      9) Pijama (comodidad y estilo, puede tener referencias sutiles a anime/videojuegos)
      $cosplayNote
      11) Deportivo (atuendo para hacer ejercicio, gimnasio o actividades al aire libre) (opcional, solo si aplica)
      Los accesorios son opcionales; no añadas por defecto.

      $otakuStyleNote

      IMPORTANTE: En todos los conjuntos, prioriza vestimenta CASUAL, CÓMODA y JUVENIL. Evita completamente blazers, chaquetas formales, trajes o ropa de oficina tradicional. La personalidad puede reflejarse sutilmente en colores vibrantes, estampados OCASIONALES (no obligatorios, solo en algunas prendas como camisetas frikis bajo americanas casuales o ropa de diario) y accesorios OPCIONALES relacionados con hobbies (no abuses de pines o complementos, úsalos solo cuando aporten valor al conjunto).

      En cada campo, describe con máximo detalle y precisión todos los rasgos físicos y visuales. Sé milimétrico en medidas, proporciones, distancias y texturas. No omitas campos.
      ''';

    final systemPromptAppearance = SystemPrompt(
      profile: AiChanProfile(
        biography: bio.biography,
        userName: bio.userName,
        aiName: bio.aiName,
        userBirthdate: bio.userBirthdate,
        aiBirthdate: bio.aiBirthdate,
        appearance: <String, dynamic>{},
      ),
      dateTime: DateTime.now(),
      instructions: {'raw': prompt},
    );

    // Reintentos con el mismo prompt/modelo para obtener JSON válido
    Log.d(
      '[IAAppearanceGenerator] Apariencia: intentos JSON (max=3) con modelo $usedModel',
    );
    const int maxJsonAttempts = 3;
    Map<String, dynamic>? appearanceMap;
    for (int attempt = 0; attempt < maxJsonAttempts; attempt++) {
      Log.d(
        '[IAAppearanceGenerator] Apariencia: intento ${attempt + 1}/$maxJsonAttempts (modelo=$usedModel)',
      );
      try {
        final AIResponse resp = await (aiService != null
            ? aiService.sendMessageImpl(
                [],
                systemPromptAppearance,
                model: usedModel,
              )
            : AIService.sendMessage(
                [],
                systemPromptAppearance,
                model: usedModel,
              ));
        if ((resp.text).trim().isEmpty) {
          Log.w(
            '[IAAppearanceGenerator] Apariencia: respuesta vacía (posible desconexión), reintentando...',
          );
          // backoff ligero
          await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
          continue;
        }
        final Map<String, dynamic> extracted = extractJsonBlock(resp.text);
        // Validación básica: extraer no vacío y contener keys esperadas
        if (extracted.isNotEmpty && extracted.keys.isNotEmpty) {
          appearanceMap = Map<String, dynamic>.from(extracted);
          Log.d(
            '[IAAppearanceGenerator] Apariencia: JSON OK en intento ${attempt + 1} (keys=${appearanceMap.keys.length})',
          );
          break;
        }
        Log.w(
          '[IAAppearanceGenerator] Apariencia: intento ${attempt + 1} sin JSON válido, reintentando...',
        );
      } catch (err) {
        if (handleRuntimeError(err, 'IAAppearanceGenerator')) {
          // logged by helper
        } else {
          Log.e(
            '[IAAppearanceGenerator] Apariencia: error de red/timeout en intento ${attempt + 1}: $err',
          );
        }
      }

      if (attempt < maxJsonAttempts - 1) {
        await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    // Si tras los intentos no hay JSON válido, cancelar sin fallback
    if (appearanceMap == null || appearanceMap.isEmpty) {
      throw Exception(
        'No se pudo generar la apariencia en formato JSON válido.',
      );
    }
    // Forzar edad_aparente=25 por consistencia (si el modelo no la puso o puso otro valor)
    try {
      appearanceMap['edad_aparente'] = 25;
    } catch (_) {}
    // Sin campo de versión: no se requiere completar timestamp
    return appearanceMap;
  }
}
