import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:ai_chan/models/ai_chan_profile.dart';
import 'package:ai_chan/services/ai_service.dart';
import '../models/system_prompt.dart';
import '../models/message.dart' as chat_model;
import '../models/timeline_entry.dart';
import '../utils/json_utils.dart';

class MemorySuperblockResult {
  final List<TimelineEntry> timeline;
  final TimelineEntry? superbloqueEntry;
  MemorySuperblockResult({required this.timeline, required this.superbloqueEntry});
}

class MemorySummaryService {
  /// Función común para pedir y extraer el resumen JSON
  Future<Map<String, dynamic>?> _getJsonSummary({
    required String instrucciones,
    required List<Map<String, dynamic>> recentMessages,
    AiChanProfile? profileOverride,
  }) async {
    // Usar solo los datos mínimos en el perfil
    final minimalProfile = AiChanProfile(
      userName: profileOverride?.userName ?? profile.userName,
      aiName: profileOverride?.aiName ?? profile.aiName,
      userBirthday: profileOverride?.userBirthday ?? profile.userBirthday,
      aiBirthday: profileOverride?.aiBirthday ?? profile.aiBirthday,
      appearance: {},
      timeline: [],
      biography: {},
    );
    final systemPrompt = SystemPrompt(
      profile: minimalProfile,
      dateTime: DateTime.now(),
      recentMessages: recentMessages,
      instructions: {'raw': instrucciones},
    );
    final response = await AIService.sendMessage([], systemPrompt, model: superblockModel);
    final resumenJson = extractJsonBlock(response.text.trim());
    if (resumenJson.toString().isNotEmpty && resumenJson.toString() != '') {
      return resumenJson;
    }
    return null;
  }

  // Esquema del JSON para resúmenes de memoria
  static const Map<String, dynamic> resumenJsonSchema = {
    'fecha_inicio': 'yyyy-mm-dd',
    'fecha_fin': 'yyyy-mm-dd',
    'eventos': [],
    'emociones': [],
    'resumen': '',
    'detalles_unicos': [], // Frases, nombres, bromas internas, datos triviales relevantes
  };
  // Prompt unificado para todos los niveles de resumen
  // Listas estáticas reutilizables
  static const List<String> _eventosClave = [
    'cumpleaños',
    'aniversario',
    'primer beso',
    'boda',
    'ruptura',
    'viaje',
    'mudanza',
    'fallecimiento',
    'nacimiento',
    'graduación',
    'ascenso',
    'despedida',
    'reconciliación',
    'hospital',
    'accidente',
    'navidad',
    'año nuevo',
    'vacaciones',
    'regalo',
    'sorpresa',
    'fiesta',
    'cena especial',
    'declaración',
    'compromiso',
    'adopción',
    'nuevo trabajo',
    'nuevo hogar',
    'nuevo miembro',
    'enfermedad',
    'amistad',
    'enemistad',
    'confesión',
    'disculpa',
    'perdón',
    'reencuentro',
  ];
  static const List<String> _temasClave = [
    'amor',
    'odio',
    'alegría',
    'tristeza',
    'miedo',
    'esperanza',
    'ansiedad',
    'confianza',
    'desconfianza',
    'enfado',
    'calma',
    'sorpresa',
    'rutina',
    'motivación',
    'desmotivación',
    'apoyo',
    'rechazo',
    'soledad',
    'compañía',
    'ilusión',
    'decepción',
    'orgullo',
    'vergüenza',
    'culpa',
    'remordimiento',
    'agradecimiento',
    'preocupación',
    'optimismo',
    'pesimismo',
    'curiosidad',
    'aburrimiento',
    'diversión',
    'tensión',
    'relajación',
    'conflicto',
    'acuerdo',
    'duda',
    'certeza',
    'inseguridad',
    'seguridad',
    'empatía',
    'frialdad',
    'cariño',
    'distancia',
    'proximidad',
    'alejamiento',
    'reconciliación',
    'ruptura',
    'amistad',
    'enemistad',
    'familia',
    'trabajo',
    'salud',
    'dinero',
    'estudios',
    'proyecto',
    'meta',
    'logro',
    'fracaso',
    'reto',
    'superación',
    'pérdida',
    'ganancia',
    'crecimiento',
    'retroceso',
    'inicio',
    'final',
    'cambio',
    'estabilidad',
    'incertidumbre',
    'claridad',
    'oscuridad',
    'espera',
    'acción',
    'pasividad',
    'actividad',
    'descanso',
    'agotamiento',
    'energía',
    'fuerza',
    'debilidad',
    'enfermedad',
    'recuperación',
    'caída',
    'levantarse',
    'viaje',
    'hogar',
    'familia',
    'amistad',
    'soledad',
    'compañía',
  ];

  // Función de detección de emociones/temas
  static List<String> _emocionesDetectadas(String texto) =>
      _temasClave.where((t) => texto.toLowerCase().contains(t)).toList();

  // Función para construir etiquetas
  static String _buildEtiquetas(String textoBloque) {
    final eventosDetectados = _eventosClave.where((e) => textoBloque.toLowerCase().contains(e)).toList();
    final emociones = _emocionesDetectadas(textoBloque);
    List<String> etiquetas = [];
    if (eventosDetectados.isNotEmpty) {
      etiquetas.add("EVENTO IMPORTANTE: ${eventosDetectados.join(', ')}");
    }
    if (emociones.isNotEmpty) {
      etiquetas.add("TEMAS/EMOCIONES: ${emociones.join(', ')}");
    }
    return etiquetas.isNotEmpty ? "[${etiquetas.join(' | ')}]\n" : "";
  }

  // Función para instrucciones de fechas exactas
  String _instruccionesFechas(Set<String> fechasUnicas) {
    String instrucciones = unifiedInstructions;
    if (fechasUnicas.length > 1) {
      instrucciones +=
          "\nIncluye SIEMPRE la fecha exacta de cada mensaje o grupo de mensajes en el resumen generado, usando el formato [yyyy-mm-dd] antes de cada fragmento resumido.";
    }
    return instrucciones;
  }

  String get unifiedInstructions {
    return "Eres un sistema de memoria, NO eres la IA del chat. Tu única tarea es generar un resumen estructurado y realista en español, solo de los mensajes o bloques proporcionados.\n\nOrganiza la información en formato de puntos, incluyendo:\n1) Hechos importantes y datos personales\n2) Emociones y estados de ánimo detectados\n3) Promesas, planes y bromas internas\n4) Cambios en la relación o temas recurrentes\n\nEn el campo 'resumen' incluye únicamente frases clave, hechos, promesas, emociones y detalles importantes, pero NUNCA el texto literal de los mensajes originales.\n\nEn el campo 'detalles_unicos' añade SOLO las frases, nombres propios, apodos, bromas internas, expresiones o datos que sean realmente únicos, recurrentes, o tengan un significado especial en la relación. Excluye cumplidos genéricos, reacciones comunes, frases triviales o cualquier elemento que no aporte valor de recuerdo a largo plazo. Prioriza lo que el usuario suele mencionar como memorable, divertido o importante. Si detectas metadatos de imagen en los mensajes (p. ej., claves 'seed' o 'prompt'), registra que hubo una imagen enviada/recibida y añade un apunte breve con el tema visual (p. ej., 'foto_usuario: <resumen corto>' o 'foto_ia: <resumen corto>'); incluye la 'seed' solo si aporta valor. Si aparecen menciones a 'quedadas AR' (realidad aumentada), trátalas como idea futura o ilusión compartida; regístralas como intención, no como evento coordinado, y anota la escena soñada si se describe.\n\nNo incluyas los mensajes originales ni referencias directas a ellos, solo la síntesis y los datos estructurados.\n\nNo respondas con saludos, introducciones, preguntas, frases de error, disculpas o negaciones. Tu respuesta debe ser únicamente el resumen estructurado en español, útil para recordar la conversación en el futuro.\n\nUsa SIEMPRE los nombres reales de los participantes: usuario = ${profile.userName.trim()}, IA = ${profile.aiName.trim()}. Respeta SIEMPRE las palabras, expresiones y el vocabulario original de los mensajes. Si aparecen propuestas de quedar en persona, anótalas como intención no viable por vivir en realidades distintas; sugiere que se sustituyan por descripciones y fotos coherentes con la relación.\n\nSi respondes de forma conversacional o con error, tu respuesta será descartada.";
  }

  // Lock de concurrencia optimizado: Completer estático compartido
  static Completer<void>? _lock;
  Future<void> _summaryQueue = Future.value();
  static String get superblockModel => dotenv.env['DEFAULT_TEXT_MODEL'] ?? '';
  final AiChanProfile profile;
  static int? get _maxHistory {
    final value = int.tryParse(dotenv.env['SUMMARY_BLOCK_SIZE'] ?? '');
    return (value != null && value > 0) ? value : null;
  }

  /// Getter público para acceder a SUMMARY_BLOCK_SIZE desde fuera
  static int? get maxHistory => _maxHistory;

  MemorySummaryService({required this.profile});

  /// Procesa resúmenes y superbloque en un solo paso: recibe mensajes, timeline y superbloque actual, y devuelve ambos actualizados
  Future<MemorySuperblockResult> processAllSummariesAndSuperblock({
    required List<chat_model.Message> messages,
    required List<TimelineEntry> timeline,
    TimelineEntry? superbloqueEntry,
    void Function(String? blockDate)? onSummaryError,
  }) async {
    // 1. Generar resúmenes de bloques si corresponde
    final updatedTimeline = await updateConversationSummary(messages, timeline, onSummaryError: onSummaryError);
    if (updatedTimeline == null) {
      return MemorySuperblockResult(timeline: timeline, superbloqueEntry: superbloqueEntry);
    }

    // 2. Procesar superbloque si corresponde
    final result = await processSuperblock(updatedTimeline, superbloqueEntry);
    return result;
  }

  /// Procesa el superbloque: si el timeline supera SUMMARY_BLOCK_SIZE entradas, condensa en un superbloque
  Future<MemorySuperblockResult> processSuperblock(
    List<TimelineEntry> timeline,
    TimelineEntry? superbloqueEntry,
  ) async {
    final List<TimelineEntry> updatedTimeline = List.from(timeline);
    TimelineEntry? updatedSuperbloque = superbloqueEntry;
    final maxHistory = _maxHistory ?? 32;
    final blocksLevel0 = updatedTimeline.where((b) => b.level == 0).toList();
    // Para superbloques de nivel superior
    for (int level = 1; level < 10; level++) {
      final blocksLevelN = updatedTimeline.where((b) => b.level == level).toList();
      if (blocksLevelN.length >= maxHistory * 2) {
        final blocksToSummarize = blocksLevelN.take(maxHistory).toList();
        if (blocksToSummarize.isNotEmpty) {
          final superbloqueStart = blocksToSummarize.first.startDate ?? '';
          final superbloqueEnd = blocksToSummarize.last.endDate ?? '';
          final resumenTexto = blocksToSummarize
              .map((b) {
                final fechaIni = b.startDate ?? '';
                final fechaFin = b.endDate ?? '';
                String texto = b.resume is String ? b.resume : b.resume.toString();
                final etiquetas = _buildEtiquetas(texto);
                if (etiquetas.isNotEmpty) {
                  texto = "$etiquetas$texto";
                }
                return "[$fechaIni a $fechaFin]\n$texto";
              })
              .join('\n');
          final instruccionesSuperbloque =
              "$unifiedInstructions\nSintetiza y resume los bloques proporcionados, evitando copiar literalmente los textos originales. Extrae y agrupa la información relevante, pero NO pierdas ningún detalle importante ni ninguna fecha significativa. Incluye SIEMPRE una fecha aproximada (mes, semana o rango general) en el resumen generado, antes de cada fragmento resumido. Puedes agrupar bloques cercanos temporalmente bajo una misma fecha si tiene sentido, aunque se pierdan detalles exactos. Si algún evento, mensaje o bloque corresponde a una fecha importante (cumpleaños, aniversario, primer beso, etc.), conserva y destaca la fecha exacta en el resumen. El resultado debe ser una memoria de largo plazo útil y efectiva, con todos los datos relevantes y fechas importantes bien conservadas.";
          final instruccionesSuperbloqueJson =
              "$instruccionesSuperbloque\n\nDEVUELVE ÚNICAMENTE EL BLOQUE JSON, SIN TEXTO EXTRA, EXPLICACIONES NI INTRODUCCIÓN. El formato debe ser:\n$resumenJsonSchema\n\nResumen de los bloques:\n$resumenTexto";
          final resumenJson = await _getJsonSummary(
            instrucciones: instruccionesSuperbloqueJson,
            recentMessages: [],
            profileOverride: AiChanProfile(
              userName: profile.userName,
              aiName: profile.aiName,
              userBirthday: profile.userBirthday,
              aiBirthday: profile.aiBirthday,
              appearance: {},
              timeline: [],
              biography: {},
            ),
          );
          if (resumenJson != null) {
            final int newLevel = level + 1;
            final superbloque = TimelineEntry(
              resume: resumenJson,
              startDate: superbloqueStart, // ISO8601 con hora
              endDate: superbloqueEnd, // ISO8601 con hora
              level: newLevel,
            );
            updatedTimeline.removeWhere((e) => blocksToSummarize.contains(e));
            int insertIndex = updatedTimeline.indexWhere((e) => e.level > level);
            if (insertIndex == -1) {
              updatedTimeline.add(superbloque);
            } else {
              updatedTimeline.insert(insertIndex, superbloque);
            }
            updatedSuperbloque = superbloque;
          }
        }
      }
    }
    // Solo condensar bloques antiguos cuando haya al menos 2xmaxHistory bloques normales
    if (blocksLevel0.length >= maxHistory * 2) {
      // Resumir solo los 32 más antiguos, dejar los 32 siguientes intactos
      final blocksToSummarize = blocksLevel0.take(maxHistory).toList();
      if (blocksToSummarize.isNotEmpty) {
        final superbloqueStart = blocksToSummarize.first.startDate ?? '';
        final superbloqueEnd = blocksToSummarize.last.endDate ?? '';
        final resumenTexto = blocksToSummarize
            .map((b) {
              final fechaIni = b.startDate ?? '';
              final fechaFin = b.endDate ?? '';
              String texto = b.resume is String ? b.resume : b.resume.toString();
              return "[$fechaIni a $fechaFin]\n$texto";
            })
            .join('\n');
        final instruccionesSuperbloque =
            "$unifiedInstructions\nIncluye SIEMPRE una fecha aproximada (mes, semana o rango general) en el resumen generado, antes de cada fragmento resumido. Puedes agrupar bloques cercanos temporalmente bajo una misma fecha si tiene sentido, aunque se pierdan detalles exactos. Si algún evento, mensaje o bloque corresponde a una fecha importante (cumpleaños, aniversario, primer beso, etc.), conserva y destaca la fecha exacta en el resumen.";
        final instruccionesSuperbloqueJson =
            "$instruccionesSuperbloque\n\nDEVUELVE ÚNICAMENTE EL BLOQUE JSON, SIN TEXTO EXTRA, EXPLICACIONES NI INTRODUCCIÓN. El formato debe ser:\n$resumenJsonSchema\n\nResumen de los bloques:\n$resumenTexto";
        final resumenJson = await _getJsonSummary(
          instrucciones: instruccionesSuperbloqueJson,
          recentMessages: [],
          profileOverride: AiChanProfile(
            userName: profile.userName,
            aiName: profile.aiName,
            userBirthday: profile.userBirthday,
            aiBirthday: profile.aiBirthday,
            appearance: {},
            timeline: [],
            biography: {},
          ),
        );
        if (resumenJson != null) {
          final int newLevel =
              (blocksToSummarize.map((b) => b.level).fold<int>(0, (prev, l) => l > prev ? l : prev)) + 1;
          final superbloque = TimelineEntry(
            resume: resumenJson,
            startDate: superbloqueStart, // ISO8601 con hora
            endDate: superbloqueEnd, // ISO8601 con hora
            level: newLevel,
          );
          updatedTimeline.removeWhere((e) => blocksToSummarize.contains(e));
          int insertIndex = updatedTimeline.indexWhere((e) => e.level > 0);
          if (insertIndex == -1) {
            updatedTimeline.add(superbloque);
          } else {
            updatedTimeline.insert(insertIndex, superbloque);
          }
          updatedSuperbloque = superbloque;
        }
      }
    }
    // Ordenar timeline por startDate antes de devolver
    updatedTimeline.sort((a, b) => (a.startDate ?? '').compareTo(b.startDate ?? ''));
    return MemorySuperblockResult(timeline: updatedTimeline, superbloqueEntry: updatedSuperbloque);
  }

  /// Genera resúmenes de bloques de mensajes y los añade al timeline si corresponde
  Future<List<TimelineEntry>?> updateConversationSummary(
    List<chat_model.Message> messages,
    List<TimelineEntry> timeline, {
    void Function(String? blockDate)? onSummaryError,
  }) async {
    // Lock de concurrencia optimizado: solo una ejecución a la vez
    while (_lock != null) {
      debugPrint('[MemorySummaryService] Resumen ya en curso, esperando a que termine...');
      await _lock!.future;
      debugPrint('[MemorySummaryService] Resumen anterior finalizado, no se relanza.');
      return null;
    }
    debugPrint('[MemorySummaryService] Iniciando proceso de resumen...');
    _lock = Completer<void>();
    try {
      // Filtrar mensajes sin texto válido
      messages = messages.where((m) => m.text.trim().isNotEmpty).toList();
      // Excluir mensajes ya cubiertos por el superbloque más reciente
      final superbloques = timeline.where((t) => t.level > 0).toList();
      if (superbloques.isNotEmpty) {
        // Tomar el superbloque más reciente por endDate
        superbloques.sort((a, b) => (b.endDate ?? '').compareTo(a.endDate ?? ''));
        final lastSuperbloqueEnd = superbloques.first.endDate;
        if (lastSuperbloqueEnd != null && lastSuperbloqueEnd.isNotEmpty) {
          messages = messages.where((m) => m.dateTime.isAfter(DateTime.parse(lastSuperbloqueEnd))).toList();
        }
      }
      final maxHistory = _maxHistory;
      if (maxHistory == null || maxHistory <= 0) {
        debugPrint(
          '[MemorySummaryService] SUMMARY_BLOCK_SIZE no está definido o es inválido. No se generarán resúmenes.',
        );
        return timeline;
      }
      if (messages.length <= maxHistory) {
        debugPrint('[MemorySummaryService] No hay suficientes mensajes para resumir.');
        return timeline;
      }

      // Siempre crear bloques de nivel 0 cada 32 mensajes, aunque ya existan resúmenes previos
      if (messages.length >= maxHistory) {
        int numBlocks = messages.length ~/ maxHistory;
        List<List<chat_model.Message>> bloquesPendientes = [];
        for (int i = 0; i < numBlocks; i++) {
          final block = messages.sublist(i * maxHistory, (i + 1) * maxHistory);
          final blockStartDate = block.first.dateTime.toIso8601String();
          final blockEndDate = block.last.dateTime.toIso8601String();
          final exists = timeline.any(
            (t) => t.startDate == blockStartDate && t.endDate == blockEndDate && t.level == 0,
          );
          if (!exists) {
            bloquesPendientes.add(block);
          }
        }
        debugPrint('[MemorySummaryService] Bloques pendientes de resumen: ${bloquesPendientes.length}');
        for (final block in bloquesPendientes) {
          final blockStartDate = block.first.dateTime.toIso8601String();
          final blockEndDate = block.last.dateTime.toIso8601String();
          debugPrint('[MemorySummaryService] Resumiendo bloque: $blockStartDate a $blockEndDate');
          _summaryQueue = _summaryQueue.then((_) => _summarizeBlock(block, timeline, onSummaryError));
          await _summaryQueue;
        }
        timeline.sort((a, b) => (a.startDate ?? '').compareTo(b.startDate ?? ''));
        debugPrint('[MemorySummaryService] Proceso de resumen finalizado.');
        return timeline;
      }

      // Ordenar timeline por startDate antes de devolver
      timeline.sort((a, b) => (a.startDate ?? '').compareTo(b.startDate ?? ''));
      debugPrint('[MemorySummaryService] Proceso de resumen finalizado.');
      return timeline;
    } catch (e, stack) {
      debugPrint('[MemorySummaryService] Error inesperado en resumen: $e\n$stack');
      rethrow;
    } finally {
      _lock?.complete();
      _lock = null;
    }
  }

  Future<void> _summarizeBlock(
    List<chat_model.Message> block,
    List<TimelineEntry> timeline,
    void Function(String? blockDate)? onSummaryError,
  ) async {
    final blockStartDate = block.first.dateTime.toIso8601String();
    final blockEndDate = block.last.dateTime.toIso8601String();
    int retryCount = 0;
    // Variable summary eliminada porque no se usa
    // Unir todos los textos del bloque para análisis semántico
    // Variable textoBloque eliminada porque no se usa
    // Crear instrucciones y mensajes para el bloque
    final fechasUnicas = block.map((m) => m.dateTime.toIso8601String().substring(0, 10)).toSet();
    String instruccionesBloque =
        "${_instruccionesFechas(fechasUnicas)}\n\nDEVUELVE ÚNICAMENTE EL BLOQUE JSON, SIN TEXTO EXTRA, EXPLICACIONES NI INTRODUCCIÓN. El formato debe ser:\n$resumenJsonSchema";
    final recentMessages = block.map((m) {
      String content = m.text.trim();
      final imgPrompt = (m.isImage && m.image != null) ? (m.image!.prompt?.trim() ?? '') : '';
      if (imgPrompt.isNotEmpty) {
        final caption = '[img_caption]$imgPrompt[/img_caption]';
        content = content.isEmpty ? caption : '$caption\n\n$content';
      }
      final role = m.sender == chat_model.MessageSender.user
          ? 'user'
          : m.sender == chat_model.MessageSender.assistant
          ? 'assistant'
          : m.sender == chat_model.MessageSender.system
          ? 'system'
          : 'unknown';
      final map = <String, dynamic>{'role': role, 'content': content, 'datetime': m.dateTime.toIso8601String()};
      if (m.isImage && m.image != null && (m.image!.seed != null && m.image!.seed!.isNotEmpty)) {
        map['seed'] = m.image!.seed;
      }
      return map;
    }).toList();
    // Intentar obtener el resumen JSON con reintentos
    Map<String, dynamic>? resumenJson;
    // Variable retryCount eliminada porque no se usa
    do {
      resumenJson = await _getJsonSummary(instrucciones: instruccionesBloque, recentMessages: recentMessages);
      if (resumenJson != null) break;
      await Future.delayed(Duration(seconds: 8));
      retryCount++;
    } while (retryCount < 8);
    if (resumenJson != null) {
      // Evitar duplicados: no añadir si ya existe un bloque con mismo rango y nivel
      final exists = timeline.any((t) => t.startDate == blockStartDate && t.endDate == blockEndDate && t.level == 0);
      if (!exists) {
        // Guardar fecha con hora exacta en los bloques
        timeline.add(
          TimelineEntry(
            resume: resumenJson,
            startDate: blockStartDate, // ISO8601 con hora
            endDate: blockEndDate, // ISO8601 con hora
            level: 0,
          ),
        );
      } else {
        debugPrint('[MemorySummaryService] Ya existe un bloque con mismo rango y nivel, no se añade.');
      }
    } else {
      if (onSummaryError != null) {
        try {
          onSummaryError(blockStartDate);
        } catch (e, stack) {
          debugPrint('[MemorySummaryService] Error en onSummaryError callback: $e\n$stack');
        }
      }
      debugPrint(
        '[MemorySummaryService] No se pudo generar resumen para el bloque $blockStartDate tras $retryCount intentos.',
      );
    }
  }
}
