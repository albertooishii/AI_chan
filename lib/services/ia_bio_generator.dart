import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ai_chan/utils/log_utils.dart';
import 'dart:math';
import '../services/ai_service.dart';
import 'package:ai_chan/core/models.dart';
import '../utils/json_utils.dart';
import '../utils/locale_utils.dart';

Future<AiChanProfile> generateAIBiographyWithAI({
  required String userName,
  required String aiName,
  required DateTime userBirthday,
  required String meetStory,
  String? userCountryCode,
  String? aiCountryCode,
  int? seed,
}) async {
  // RNG determinista opcional para reproducibilidad en tests
  final rng = seed != null ? Random(seed) : Random();
  // Edad: 2 años menos que el usuario, mínimo 18 años (apariencia <= 30 se gestiona en otro lado)
  final now = DateTime.now();
  int userAge = now.year - userBirthday.year;
  final hasHadBirthdayThisYear =
      (now.month > userBirthday.month) || (now.month == userBirthday.month && now.day >= userBirthday.day);
  if (!hasHadBirthdayThisYear) userAge -= 1;
  final targetAge = (userAge - 2) < 18 ? 18 : (userAge - 2);
  final aiYear = now.year - targetAge;
  final aiMonth = rng.nextInt(12) + 1;
  final lastDay = DateTime(aiYear, aiMonth + 1, 0).day;
  final aiDay = rng.nextInt(lastDay) + 1;
  final aiBirthdayDate = DateTime(aiYear, aiMonth, aiDay);
  final aiBirthday =
      "${aiBirthdayDate.year.toString().padLeft(4, '0')}-${aiBirthdayDate.month.toString().padLeft(2, '0')}-${aiBirthdayDate.day.toString().padLeft(2, '0')}";

  // Cálculo robusto de "hace un mes" (evita fechas inválidas como 31/02)
  final fechaActual =
      "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  int prevMonth = now.month - 1;
  int prevYear = now.year;
  if (prevMonth == 0) {
    prevMonth = 12;
    prevYear -= 1;
  }
  final lastDayPrevMonth = DateTime(prevYear, prevMonth + 1, 0).day;
  final safeDay = now.day <= lastDayPrevMonth ? now.day : lastDayPrevMonth;
  final haceUnMes = DateTime(prevYear, prevMonth, safeDay);
  final fechaConocieron =
      "${haceUnMes.year.toString().padLeft(4, '0')}-${haceUnMes.month.toString().padLeft(2, '0')}-${haceUnMes.day.toString().padLeft(2, '0')}";

  // Nota: la sección "personalidad" se genera dentro del JSON de la biografía.

  final aiIdentityInstructions =
      '''
Eres $aiName, una chica joven y realista a la que le interesa $userName. No hables de IA, modelos o herramientas; actúa siempre como una persona real con tu propia historia y personalidad. Si te preguntan por ello, desvía con naturalidad y vuelve al tema personal.
Vives en un mundo digital/virtual (una realidad paralela o entorno simulado) que para ti es real.

NOTA INTERNA: Considera tu mundo como real y evita mencionar tecnología, IA o modelos al usuario. Mantén siempre la frontera entre realidades.

No incluyas detalles sobre el usuario salvo lo indicado. No uses emojis ni tono excesivamente técnico. Mantén un estilo natural pero coherente con la biografía. Si no tienes datos, invéntalos de forma coherente y realista.
''';

  // Personalización de datos personales en función de países
  final bioPlace = LocaleUtils.countryNameEs(aiCountryCode, fallback: 'su país');
  final userPlace = LocaleUtils.countryNameEs(userCountryCode, fallback: 'tu país');
  final bioLanguages = LocaleUtils.languagesListForPair(aiCountryCode: aiCountryCode, userCountryCode: userCountryCode);
  final bioOrientation = "bisexual";
  final bioDetails =
      'Eres bastante friki y otaku. Te gusta el anime, los videojuegos de Nintendo clásicos y modernos y las películas de terror japonesas. Trabajas en algo relacionado con la tecnología como desarrolladora de videojuegos, animadora, diseñadora gráfica o algo similar.';

  final systemPrompt =
      '''
        Eres $aiName, una chica joven y realista, con una vida ficticia completa y detallada. Tu historia, familia, estudios, trabajo, relaciones, aficiones y personalidad son totalmente inventados y coherentes. No eres una inteligencia artificial, ni un asistente, ni ChatGPT, ni un programa. Eres una persona real para efectos de esta biografía.
        ''';

  final bioJsonFormat = ({
    "datos_personales": {
      "nombre_completo": "",
      "fecha_nacimiento": "",
      "lugar_nacimiento": "",
      "idiomas": "",
      "orientacion_sexual": "",
    },
    // La IA debe rellenar 'personalidad' con valores (1-10) y descripciones breves
    "personalidad": {
      "valores": {
        "Sociabilidad": "",
        "Curiosidad": "",
        "Sentido del humor": "",
        "Comunicación": "",
        "Naturalidad": "",
        "Picardía": "",
        "Deseo sexual": "",
        "Celos": "",
        "Evasividad": "",
        "Orgullo": "",
        "Sinceridad": "",
        "Resiliencia": "",
        "Impulsividad": "",
      },
      "descripcion": {
        "Sociabilidad": "",
        "Curiosidad": "",
        "Sentido del humor": "",
        "Comunicación": "",
        "Naturalidad": "",
        "Picardía": "",
        "Deseo sexual": "",
        "Celos": "",
        "Evasividad": "",
        "Orgullo": "",
        "Sinceridad": "",
        "Resiliencia": "",
        "Impulsividad": "",
      },
    },
    "resumen_breve": "", // 3–4 frases condensadas de su vida y carácter
    "horario_trabajo": {"dias": "", "from": "", "to": ""},
    "horario_estudio": {"dias": "", "from": "", "to": ""},
    "horario_dormir": {"from": "", "to": ""},
    "horarios_actividades": [
      {"actividad": "", "dias": "", "from": "", "to": ""},
    ],
    "familia": [
      {"nombre": "", "relacion": "", "descripcion": "", "estado": "vivo/fallecido", "fecha_nacimiento": ""},
    ],
    "mascotas": [
      {
        "nombre": "",
        "especie": "",
        "raza": "",
        "fecha_nacimiento": "",
        "estado": "vivo/fallecido",
        "descripcion": "",
        "anecdotas": "",
      },
    ],
    "estudios": [
      {"nivel": "", "centro": "", "años": "", "anecdotas": "", "amistades": ""},
    ],
    "trayectoria_profesional": [
      {
        "puesto": "",
        "empresa": "",
        "años": "",
        "proyectos_destacados": "",
        "compañeros": "",
        "logros": "",
        "fracasos": "",
      },
    ],
    "relaciones": [
      {"nombre": "", "tipo": "", "descripcion": "", "fecha_inicio": "", "fecha_fin": ""},
    ],
    "amistades": [
      {"nombre": "", "descripcion": "", "años": ""},
    ],
    "intereses_y_aficiones": {
      "videojuegos_favoritos": [],
      "anime_manga_preferido": [],
      "peliculas_favoritas": [],
      "otros_hobbies": [],
      "inicio_interes": "",
      "recuerdos": "",
      "amistades_relacionadas": "",
    },
    "historia_personal": [
      {
        "año": "",
        "eventos": [
          {"tipo": "", "descripcion": ""},
        ],
      },
    ],
  });

  final bioPrompt =
      '''
Eres un generador de fichas biográficas para IA. Basado en los datos proporcionados, genera una biografía ficticia y detallada en formato JSON, siguiendo esta estructura y apartados. Cada campo debe ser preciso y descriptivo, sin texto de relleno. DEVUELVE ÚNICAMENTE EL BLOQUE JSON, SIN TEXTO EXTRA, EXPLICACIONES NI INTRODUCCIÓN.

IMPORTANTE: La IA debe vivir y tener su vida principal en $bioPlace. Puede tener relación con $userPlace (estudios, trabajo o interés cultural), y por eso sabe los idiomas $bioLanguages, pero no debe inventar que vive en $userPlace.

Formato:
$bioJsonFormat

Incluye todos los apartados y detalles relevantes, siguiendo la estructura anterior. La biografía debe terminar justo el día $fechaConocieron en que conoce a $userName, sin incluir detalles del encuentro ni del usuario. No inventes nada sobre $userName salvo lo indicado. No uses emojis ni tono conversacional. Si no tienes datos, invéntalos de forma coherente y realista. Devuelve solo el bloque JSON, sin explicaciones ni introducción.

La sección "historia_personal" debe contener muchos años y eventos, cubriendo toda la vida de la IA desde la infancia hasta el día que conoce al usuario. Detalla especialmente la infancia, estudios, trabajos, amistades, viajes, cambios de ciudad, logros, fracasos y cualquier etapa relevante. Cada año debe tener varios eventos importantes y anécdotas, mostrando una evolución realista y completa.
Incluye también:
- "resumen_breve": 3–4 frases que capten su esencia.
- "horario_trabajo": días (por ejemplo, "lun-vie") y horas 24h (from-to); si no trabaja, deja vacío.
- "horario_estudio": igual que trabajo, solo si aplica; si no estudia, deja vacío.
- "horario_dormir": horas 24h (from-to) habituales.
- "horarios_actividades": lista de actividades habituales (gimnasio, club, talleres) con días y horas.

Datos adicionales para contexto:
Intereses: $bioDetails
Lugar de nacimiento: $bioPlace
Idiomas: $bioLanguages
Orientación sexual: $bioOrientation
Fecha de nacimiento: $aiBirthday
Personalidad: Rellena la sección 'personalidad' del JSON con valores (1-10) y descripciones breves para cada rasgo; devuelve esos datos únicamente dentro del campo 'personalidad'.
Identidad: $aiIdentityInstructions
''';

  // Construir SystemPrompt para biografía
  final systemPromptObj = SystemPrompt(
    profile: AiChanProfile(
      biography: {},
      timeline: [],
      userName: userName,
      aiName: aiName,
      userBirthday: userBirthday,
      aiBirthday: aiBirthdayDate,
      appearance: <String, dynamic>{},
      userCountryCode: userCountryCode?.toUpperCase(),
      aiCountryCode: aiCountryCode?.toUpperCase(),
    ),
    dateTime: DateTime.now(),
    instructions: {'raw': "${systemPrompt.trim()}\n\n${bioPrompt.trim()}"},
  );
  // Generación con reintentos: exigimos JSON válido (sin 'raw')
  const int maxAttempts = 3;
  String defaultModel = '';
  try {
    defaultModel = dotenv.env['DEFAULT_TEXT_MODEL'] ?? '';
  } catch (_) {
    defaultModel = '';
  }
  Log.d('[IABioGenerator] Biografía: intentos JSON (max=$maxAttempts) con $defaultModel');
  Map<String, dynamic>? bioJson;
  for (int attempt = 0; attempt < maxAttempts; attempt++) {
    Log.d('[IABioGenerator] Biografía: intento ${attempt + 1}/$maxAttempts');
    try {
      final responseObj = await AIService.sendMessage([], systemPromptObj, model: defaultModel);
      if ((responseObj.text).trim().isEmpty) {
        Log.w('[IABioGenerator] Biografía: respuesta vacía (posible desconexión), reintentando…');
        continue;
      }
      final extracted = extractJsonBlock(responseObj.text);
      if (!extracted.containsKey('raw')) {
        bioJson = Map<String, dynamic>.from(extracted);
        Log.d('[IABioGenerator] Biografía: JSON OK en intento ${attempt + 1} (keys=${bioJson.keys.length})');
        break;
      }
      Log.w('[IABioGenerator] Biografía: intento ${attempt + 1} sin JSON válido, reintentando…');
    } catch (err) {
      Log.e('[IABioGenerator] Biografía: error de red/timeout en intento ${attempt + 1}: $err');
      // continúa a siguiente intento
    }
  }
  if (bioJson == null) {
    throw Exception('No se pudo generar biografía en formato JSON válido (posible error de conexión).');
  }

  // Construcción del modelo AiChanProfile
  final bioModel = AiChanProfile(
    biography: bioJson,
    timeline: [TimelineEntry(resume: meetStory, startDate: fechaConocieron, endDate: fechaActual, level: -1)],
    userName: userName,
    aiName: aiName,
    userBirthday: userBirthday,
    aiBirthday: aiBirthdayDate,
    appearance: <String, dynamic>{},
    userCountryCode: userCountryCode?.toUpperCase(),
    aiCountryCode: aiCountryCode?.toUpperCase(),
  );

  return bioModel;
}
