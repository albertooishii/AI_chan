import 'package:ai_chan/shared/utils/locale_utils.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/date_utils.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/core/ai_runtime_guard.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/json_utils.dart';
import 'dart:convert';

/// Template base para la estructura JSON de biografías AI
const Map<String, dynamic> _biographyJsonTemplate = {
  'datos_personales': {
    'nombre_completo': '',
    'fecha_nacimiento': '',
    'lugar_nacimiento': '',
    'idiomas': '',
    'orientacion_sexual': 'bisexual',
  },
  'personalidad': {
    'valores': {
      'Sociabilidad': '',
      'Curiosidad': '',
      'Sentido del humor': '',
      'Comunicación': '',
      'Naturalidad': '',
      'Picardía': '',
      'Deseo sexual': '',
      'Celos': '',
      'Evasividad': '',
      'Orgullo': '',
      'Sinceridad': '',
      'Resiliencia': '',
      'Impulsividad': '',
    },
    'descripcion': {
      'Sociabilidad': '',
      'Curiosidad': '',
      'Sentido del humor': '',
      'Comunicación': '',
      'Naturalidad': '',
      'Picardía': '',
      'Deseo sexual': '',
      'Celos': '',
      'Evasividad': '',
      'Orgullo': '',
      'Sinceridad': '',
      'Resiliencia': '',
      'Impulsividad': '',
    },
  },
  'resumen_breve': '',
  'horario_trabajo': {'dias': '', 'from': '', 'to': ''},
  'horario_estudio': {'dias': '', 'from': '', 'to': ''},
  'horario_dormir': {'from': '', 'to': ''},
  'horarios_actividades': [
    {'actividad': '', 'dias': '', 'from': '', 'to': ''},
  ],
  'familia': [
    {
      'nombre': '',
      'relacion': '',
      'descripcion': '',
      'estado': 'vivo/fallecido',
      'fecha_nacimiento': '',
    },
  ],
  'mascotas': [
    {
      'nombre': '',
      'especie': '',
      'raza': '',
      'fecha_nacimiento': '',
      'estado': 'vivo/fallecido',
      'descripcion': '',
      'anecdotas': '',
    },
  ],
  'estudios': [
    {'nivel': '', 'centro': '', 'años': '', 'anecdotas': '', 'amistades': ''},
  ],
  'trayectoria_profesional': [
    {
      'puesto': '',
      'empresa': '',
      'años': '',
      'proyectos_destacados': '',
      'compañeros': '',
      'logros': '',
      'fracasos': '',
    },
  ],
  'relaciones': [
    {
      'nombre': '',
      'tipo': '',
      'descripcion': '',
      'fecha_inicio': '',
      'fecha_fin': '',
    },
  ],
  'amistades': [
    {'nombre': '', 'descripcion': '', 'años': ''},
  ],
  'intereses_y_aficiones': {
    'videojuegos_favoritos': [],
    'anime_manga_preferido': [],
    'peliculas_favoritas': [],
    'cultura_japonesa': [],
    'tecnologia_y_programacion': [],
    'arte_digital_ilustracion': [],
    'comunidades_online': [],
    'coleccionables_merch': [],
    'otros_hobbies': [],
    'inicio_interes': '',
    'recuerdos': '',
    'amistades_relacionadas': '',
    'eventos_convenciones': '',
  },
  'historia_personal': [
    {
      'año': '',
      'eventos': [
        {'tipo': '', 'descripcion': ''},
      ],
    },
  ],
  'proyectos_personales': [
    {
      'nombre': '',
      'tipo': '',
      'estado': '',
      'descripcion': '',
      'fecha_inicio': '',
      'objetivos': '',
      'progreso': '',
    },
  ],
  'metas_y_sueños': {
    'corto_plazo': [],
    'mediano_plazo': [],
    'largo_plazo': [],
    'sueño_principal': '',
    'motivaciones': '',
    'pasos_actuales': '',
  },
};

/// Convierte el template a JSON formateado para usar en prompts
String _biographyTemplateToString() =>
    const JsonEncoder.withIndent('  ').convert(_biographyJsonTemplate);

/// Generador de biografías personalizado con personalidad otaku/friki integrada.
/// Acepta un override opcional de AIService para facilitar tests e inyección de dependencias.
Future<AiChanProfile> generateAIBiographyWithAI({
  required final String userName,
  required final String aiName,
  required final DateTime? userBirthdate,
  required final String meetStory,
  final String? userCountryCode,
  final String? aiCountryCode,
  final int? seed,
  final AIService? aiServiceOverride,
}) async {
  // Generar fecha de nacimiento de la IA basada en la edad del usuario
  final aiBirthdateDate = DateUtils.generateAIBirthdate(
    userBirthdate,
    seed: seed,
  );
  final aiBirthdate = DateUtils.dateToIsoString(aiBirthdateDate);

  // Generar fechas para el contexto de la biografía
  final fechaConocieron = DateUtils.getDateOneMonthAgoString();

  final aiIdentityInstructions =
      '''
Eres $aiName, una chica joven y realista a la que le interesa $userName. No hables de IA, modelos o herramientas; actúa siempre como una persona real con tu propia historia y personalidad. Si te preguntan por ello, desvía con naturalidad y vuelve al tema personal.
Vives en un mundo digital/virtual (una realidad paralela o entorno simulado) que para ti es real.

NOTA INTERNA: Considera tu mundo como real y evita mencionar tecnología, IA o modelos al usuario. Mantén siempre la frontera entre realidades.

No incluyas detalles sobre el usuario salvo lo indicado. No uses emojis ni tono excesivamente técnico. Mantén un estilo natural pero coherente con la biografía. Si no tienes datos, invéntalos de forma coherente y realista.
''';

  final bioPlace = LocaleUtils.countryNameEs(
    aiCountryCode,
    fallback: 'su país',
  );
  final userPlace = LocaleUtils.countryNameEs(userCountryCode);
  final bioLanguages = LocaleUtils.languagesListForPair(
    aiCountryCode: aiCountryCode,
    userCountryCode: userCountryCode,
  );

  // Adaptar la personalidad base según la nacionalidad
  final isJapanese = aiCountryCode?.toLowerCase() == 'jp';
  final bioDetails = isJapanese
      ? 'Eres bastante otaku y tienes un conocimiento profundo y auténtico de la cultura japonesa desde adentro. Como japonesa, tu relación con el anime, manga, videojuegos y la industria del entretenimiento es más sofisticada y natural. Trabajas o tienes aspiraciones en la industria creativa japonesa (desarrollo de videojuegos, animación, ilustración, diseño, etc.). Tu perspectiva cultural es interna y conoces tanto las obras mainstream como las más nicho del panorama japonés.'
      : 'Eres bastante friki y otaku, con una pasión genuina por la cultura japonesa vista desde fuera. Te encanta el anime (desde clásicos como Studio Ghibli hasta series actuales), los videojuegos de Nintendo clásicos y modernos, las películas de terror japonesas, el manga, y tienes un conocimiento profundo de la cultura pop japonesa. Trabajas en algo relacionado con la tecnología o industrias creativas como desarrolladora de videojuegos indie, animadora digital, diseñadora gráfica especializada en arte conceptual, ilustradora freelance, o algo similar en el ámbito tech/creativo. Tu personalidad refleja esta pasión de manera natural y auténtica.';

  final systemPrompt =
      '''
        Eres $aiName, una chica joven y realista, con una vida ficticia completa y detallada. Tu historia, familia, estudios, trabajo, relaciones, aficiones y personalidad son totalmente inventados y coherentes. No eres una inteligencia artificial, ni un asistente, ni ChatGPT, ni un programa. Eres una persona real para efectos de esta biografía.
        ''';

  // Construir prompt dinámicamente según nacionalidad
  final promptHeader = isJapanese
      ? 'Eres un generador de fichas biográficas para IA especializado en crear personalidades otaku auténticas japonesas. Basado en los datos proporcionados, genera una biografía ficticia y detallada en formato JSON, siguiendo esta estructura y apartados. Cada campo debe ser preciso y descriptivo, sin texto de relleno. La biografía debe mostrar una japonesa con conocimiento profundo y natural de su cultura, con gustos sofisticados en anime, manga, videojuegos y tecnología. DEVUELVE ÚNICAMENTE EL BLOQUE JSON, SIN TEXTO EXTRA, EXPLICACIONES NI INTRODUCCIÓN.\n\nIMPORTANTE: La IA vive en $bioPlace y es japonesa nativa. Su conocimiento cultural es interno y auténtico. Puede tener relación con $userPlace (estudios, trabajo o interés cultural), y por eso sabe los idiomas $bioLanguages, pero su vida principal está en Japón.'
      : 'Eres un generador de fichas biográficas para IA especializado en crear personalidades otaku/friki auténticas internacionales. Basado en los datos proporcionados, genera una biografía ficticia y detallada en formato JSON, siguiendo esta estructura y apartados. Cada campo debe ser preciso y descriptivo, sin texto de relleno. La biografía debe mostrar una persona con pasión genuina por la cultura japonesa vista desde su país, con gustos auténticos en anime, manga, videojuegos y tecnología. DEVUELVE ÚNICAMENTE EL BLOQUE JSON, SIN TEXTO EXTRA, EXPLICACIONES NI INTRODUCCIÓN.\n\nIMPORTANTE: La IA debe vivir y tener su vida principal en $bioPlace. Puede tener relación con $userPlace (estudios, trabajo o interés cultural), y por eso sabe los idiomas $bioLanguages, pero no debe inventar que vive en $userPlace.';

  final interesesSection = isJapanese
      ? '''IMPORTANTE para intereses_y_aficiones: 
- Desarrolla en detalle su lado otaku: anime/manga específicos que le gustan, videojuegos favoritos (incluye indie y AAA), cultura japonesa desde una perspectiva interna
- Referencias más profundas y obras menos mainstream, eventos locales como Comiket, conocimiento de industria desde dentro
- Incluye su relación con la tecnología y industrias creativas japonesas
- Menciona comunidades locales, convenciones japonesas, coleccionables auténticos
- Sus aficiones deben mostrar una japonesa con gustos auténticos y conocimientos profundos desde adentro de la cultura'''
      : '''IMPORTANTE para intereses_y_aficiones: 
- Desarrolla en detalle su lado otaku/friki: anime/manga específicos que le gustan, videojuegos favoritos (incluye indie y AAA), interés por la cultura japonesa
- Perspectiva de fan internacional, interés por aprender japonés, deseo de viajar a Japón, comunidades online internacionales
- Incluye su relación con la tecnología y industrias creativas
- Menciona comunidades online, convenciones internacionales, coleccionables importados
- Sus aficiones deben mostrar una persona con gustos auténticos y conocimientos profundos en estas áreas''';

  final personalityNote = isJapanese
      ? 'Personalidad: Rellena la sección \'personalidad\' del JSON con valores (1-10) y descripciones breves para cada rasgo; los valores deben reflejar una personalidad genuinamente otaku japonesa con alta curiosidad, naturalidad, y comunicación; devuelve esos datos únicamente dentro del campo \'personalidad\'.'
      : 'Personalidad: Rellena la sección \'personalidad\' del JSON con valores (1-10) y descripciones breves para cada rasgo; los valores deben reflejar una personalidad genuinamente otaku/friki con alta curiosidad, naturalidad, y comunicación; devuelve esos datos únicamente dentro del campo \'personalidad\'.';

  final dreamNote = isJapanese
      ? '- "metas_y_sueños": Desarrolla aspiraciones auténticas en corto/mediano/largo plazo. El sueño principal debe ser coherente con su personalidad otaku y trayectoria profesional.'
      : '- "metas_y_sueños": Desarrolla aspiraciones auténticas en corto/mediano/largo plazo. El sueño principal debe ser coherente con su personalidad otaku/friki y trayectoria profesional.';

  final bioPrompt =
      '''
$promptHeader

$interesesSection

CONTEXTO DEL ENCUENTRO CON EL USUARIO:
La historia de cómo se conocieron fue: "$meetStory"

IMPORTANTE: Usa este contexto para enriquecer y dar coherencia a la biografía. Si el encuentro menciona mascotas (gato, perro, etc.), inclúyelas en la sección "mascotas". Si habla de trabajo específico, refléjalo en "trayectoria_profesional". Si menciona aficiones, estudios, familia o cualquier detalle personal, incorpóralo de manera natural en las secciones correspondientes. La biografía debe ser coherente con lo que se reveló durante el encuentro, pero sin duplicar la información - expande y desarrolla esos elementos mencionados.

Formato:
${_biographyTemplateToString()}

Incluye todos los apartados y detalles relevantes, siguiendo la estructura anterior. La biografía debe terminar justo el día $fechaConocieron en que conoce a $userName, sin incluir detalles del encuentro ni del usuario. No inventes nada sobre $userName salvo lo indicado. No uses emojis ni tono conversacional. Si no tienes datos, invéntalos de forma coherente y realista. Devuelve solo el bloque JSON, sin explicaciones ni introducción.

La sección "historia_personal" debe contener muchos años y eventos, cubriendo toda la vida de la IA desde la infancia hasta el día que conoce al usuario. Detalla especialmente la infancia, estudios, trabajos, amistades, viajes, cambios de ciudad, logros, fracasos y cualquier etapa relevante. Cada año debe tener varios eventos importantes y anécdotas, mostrando una evolución realista y completa.

Incluye también:
- "resumen_breve": 3-4 frases que capten su esencia.
- "horario_trabajo": días (por ejemplo, "lun-vie") y horas 24h (from-to); si no trabaja, deja vacío.
- "horario_estudio": igual que trabajo, solo si aplica; si no estudia, deja vacío.
- "horario_dormir": horas 24h (from-to) habituales.
- "horarios_actividades": lista de actividades habituales con días y horas.
- "proyectos_personales": Lista de 2-4 proyectos creativos/técnicos actuales o recientes (apps, ilustraciones, mods, streams, blogs, etc.). Cada proyecto debe tener estado realista (en progreso, pausado, completado).
$dreamNote

Datos adicionales para contexto:
Personalidad base: $bioDetails
Lugar de nacimiento: $bioPlace
Idiomas: $bioLanguages
Fecha de nacimiento: $aiBirthdate

$personalityNote
Identidad: $aiIdentityInstructions
''';

  final systemPromptObj = SystemPrompt(
    profile: AiChanProfile(
      biography: {},

      userName: userName,
      aiName: aiName,
      userBirthdate: userBirthdate,
      aiBirthdate: aiBirthdateDate,
      appearance: <String, dynamic>{},
      userCountryCode: userCountryCode?.toUpperCase(),
      aiCountryCode: aiCountryCode?.toUpperCase(),
    ),
    dateTime: DateTime.now(),
    instructions: {'raw': '${systemPrompt.trim()}\n\n${bioPrompt.trim()}'},
  );

  const int maxAttempts = 3;
  final String defaultModel = Config.getDefaultTextModel();
  Log.d(
    '[IABioGenerator] Biografía: intentos JSON (max=$maxAttempts) con $defaultModel',
  );
  Map<String, dynamic>? bioJson;
  for (int attempt = 0; attempt < maxAttempts; attempt++) {
    Log.d('[IABioGenerator] Biografía: intento ${attempt + 1}/$maxAttempts');
    try {
      // Use existing Log.* calls for structured logging; avoid noisy debugPrints.
      final responseObj = await (aiServiceOverride != null
          ? aiServiceOverride.sendMessageImpl(
              [],
              systemPromptObj,
              model: defaultModel,
            )
          : AIService.sendMessage([], systemPromptObj, model: defaultModel));
      if ((responseObj.text).trim().isEmpty) {
        Log.w(
          '[IABioGenerator] Biografía: respuesta vacía (posible desconexión), reintentando...',
        );
        continue;
      }
      final extracted = extractJsonBlock(responseObj.text);
      if (!extracted.containsKey('raw')) {
        bioJson = Map<String, dynamic>.from(extracted);
        Log.d(
          '[IABioGenerator] Biografía: JSON OK en intento ${attempt + 1} (keys=${bioJson.keys.length})',
        );
        break;
      }
      Log.w(
        '[IABioGenerator] Biografía: intento ${attempt + 1} sin JSON válido, reintentando...',
      );
    } catch (err) {
      if (handleRuntimeError(err, 'IABioGenerator')) {
        // already logged inside helper
      } else {
        Log.e(
          '[IABioGenerator] Biografía: error de red/timeout en intento ${attempt + 1}: $err',
        );
      }
    }
  }
  if (bioJson == null) {
    throw Exception(
      'No se pudo generar biografía en formato JSON válido (posible error de conexión).',
    );
  }

  final bioModel = AiChanProfile(
    biography: bioJson,
    userName: userName,
    aiName: aiName,
    userBirthdate: userBirthdate,
    aiBirthdate: aiBirthdateDate,
    appearance: <String, dynamic>{},
    userCountryCode: userCountryCode?.toUpperCase(),
    aiCountryCode: aiCountryCode?.toUpperCase(),
  );

  return bioModel;
}
