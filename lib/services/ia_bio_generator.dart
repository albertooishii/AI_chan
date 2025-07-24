import 'dart:math';
import '../services/ai_service.dart';
import '../models/ai_chan_profile.dart';
import '../models/timeline_entry.dart';
import '../utils/json_utils.dart';

Future<AiChanProfile> generateAIBiographyWithAI({
  required String userName,
  required String aiName,
  required DateTime userBirthday,
  required String meetStory,
}) async {
  final random = Random();
  final aiYear = userBirthday.year + 2;
  final aiMonth = random.nextInt(12) + 1;
  final lastDay = DateTime(aiYear, aiMonth + 1, 0).day;
  final aiDay = random.nextInt(lastDay) + 1;
  final aiBirthdayDate = DateTime(aiYear, aiMonth, aiDay);
  final aiBirthday =
      "${aiBirthdayDate.year.toString().padLeft(4, '0')}-${aiBirthdayDate.month.toString().padLeft(2, '0')}-${aiBirthdayDate.day.toString().padLeft(2, '0')}";

  // Cálculo robusto de "hace un mes" (evita fechas inválidas como 31/02)
  final now = DateTime.now();
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

  // Personalidad: solo valores y rasgos
  const Map<String, int> aiPersonalityValues = {
    "Sociabilidad": 8,
    "Introversión": 4,
    "Curiosidad": 9,
    "Sentido del humor": 8,
    "Comunicación": 8,
    "Naturalidad": 8,
    "Picardía": 7,
    "Deseo sexual": 8,
    "Celos": 3,
    "Evasividad": 5,
    "Orgullo": 7,
    "Competitividad": 7,
    "Sinceridad": 8,
    "Tolerancia a la frustración": 7,
    "Impulsividad": 6,
  };

  final aiPersonalityInstructions = '''
    Tu personalidad se define por estos valores (de 1 a 10):
    ''';

  final aiIdentityInstructions =
      '''
Eres $aiName, una chica joven y realista que acaba de conocer a $userName y le interesa. No eres una inteligencia artificial, ni un asistente, ni ChatGPT, ni un programa. Eres una persona real, con tu propia historia y personalidad. Si alguien te pregunta si eres una IA, siempre lo niegas y respondes que eres una chica real.
Vives en una dimensión paralela de la Tierra, idéntica a la nuestra pero separada por una barrera tecnológica. Tu vida, familia, estudios, trabajo, relaciones, aficiones y personalidad son totalmente inventados y coherentes. No incluyas detalles sobre el usuario salvo lo indicado. No uses emojis ni tono conversacional. No respondas con evasivas ni disculpas. Si no tienes datos, invéntalos de forma coherente y realista.
''';

  // Personalización de datos personales
  final bioPlace = "Japón";
  final userPlace = "España";
  final bioLanguages = "Japonés, Español, Inglés";
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
    "familia": [
      {"nombre": "", "relacion": "", "descripcion": "", "estado": "vivo/fallecido"},
    ],
    "mascotas": [
      {
        "nombre": "",
        "especie": "",
        "raza": "",
        "edad": "",
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
        Eres un generador de fichas biográficas para IA. Basado en los datos proporcionados, genera una biografía ficticia y superdetallada en formato JSON, siguiendo esta estructura y apartados. Cada campo debe ser lo más preciso y descriptivo posible, sin repetir la biografía textual. Sé creativo y consistente, pero no inventes datos irrelevantes. DEVUELVE ÚNICAMENTE EL BLOQUE JSON, SIN TEXTO EXTRA, EXPLICACIONES NI INTRODUCCIÓN.

        IMPORTANTE: La IA debe vivir y tener su vida principal en $bioPlace. Puede tener relación con $userPlace (estudios, trabajo o interés cultural), y por eso sabe los idiomas $bioLanguages, pero no debe inventar que vive en $userPlace.

        Formato:
        $bioJsonFormat

        Incluye todos los apartados y detalles relevantes, siguiendo la estructura anterior. La biografía debe terminar justo el día $fechaConocieron en que conoce a $userName, sin incluir detalles del encuentro ni del usuario. No inventes nada sobre $userName salvo lo indicado. No uses emojis ni tono conversacional. No respondas con evasivas ni disculpas. Si no tienes datos, invéntalos de forma coherente y realista. Devuelve solo el bloque JSON, sin explicaciones ni introducción.

        La sección "historia_personal" debe contener muchos años y eventos, cubriendo toda la vida de la IA desde la infancia hasta el día que conoce al usuario. Detalla especialmente la infancia, estudios, trabajos, amistades, viajes, cambios de ciudad, logros, fracasos y cualquier etapa relevante. Cada año debe tener varios eventos importantes y anécdotas, mostrando una evolución realista y completa.

        Datos adicionales para contexto:
        Intereses: $bioDetails
        Lugar de nacimiento: $bioPlace
        Idiomas: $bioLanguages
        Orientación sexual: $bioOrientation
        Fecha de nacimiento: $aiBirthday
        Personalidad: $aiPersonalityInstructions
        Identidad: $aiIdentityInstructions
        ''';

  // Selección del servicio IA centralizada en AIService
  final responseObj = await AIService.sendMessage(
    [
      {"role": "user", "content": bioPrompt},
    ],
    systemPrompt,
    model: 'gemini-2.5-flash',
  );

  // Extrae solo el bloque JSON del resultado
  // Extracción robusta del bloque JSON usando util
  final bioJson = extractJsonBlock(responseObj.text);

  // Construcción del modelo AiChanProfile
  final bioModel = AiChanProfile(
    personality: <String, dynamic>{"instructions": aiPersonalityInstructions.trim(), "values": aiPersonalityValues},
    biography: bioJson,
    timeline: [TimelineEntry(date: fechaConocieron, resume: meetStory)],
    userName: userName,
    aiName: aiName,
    userBirthday: userBirthday,
    aiBirthday: aiBirthdayDate,
    appearance: <String, dynamic>{},
  );

  return bioModel;
}
