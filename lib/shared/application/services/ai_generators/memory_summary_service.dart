import 'package:ai_chan/shared.dart';
// REMOVED: Flutter framework dependency to fix Clean Architecture violation
// Use LogUtils from infrastructure layer instead of debugPrint
import 'dart:async';
// Replaced legacy barrel import with canonical barrel

class MemorySuperblockResult {
  MemorySuperblockResult({
    required this.timeline,
    required this.superbloqueEntry,
  });
  final List<TimelineEntry> timeline;
  final TimelineEntry? superbloqueEntry;
}

class MemorySummaryService {
  MemorySummaryService({required this.profile});

  /// Función compacta para pedir y extraer el resumen JSON
  Future<Map<String, dynamic>?> _getJsonSummary({
    required final String instrucciones,
    required final List<Map<String, dynamic>> recentMessages,
    final AiChanProfile? profileOverride,
  }) async {
    // Usar solo los datos mínimos en el perfil
    final minimalProfile = AiChanProfile(
      userName: profileOverride?.userName ?? profile.userName,
      aiName: profileOverride?.aiName ?? profile.aiName,
      userBirthdate: profileOverride?.userBirthdate ?? profile.userBirthdate,
      aiBirthdate: profileOverride?.aiBirthdate ?? profile.aiBirthdate,
      appearance: {},

      biography: {},
    );
    final systemPrompt = SystemPrompt(
      profile: minimalProfile,
      dateTime: DateTime.now(),
      recentMessages: recentMessages,
      instructions: {'raw': instrucciones},
    );

    final response = await AIProviderManager.instance.sendMessage(
      history: [],
      systemPrompt: systemPrompt,
    );
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
    'detalles_unicos':
        [], // Frases, nombres, bromas internas, datos triviales relevantes
  };
  // Prompt unificado para todos los niveles de resumen
  // Listas estticas reutilizables
  static const List<String> _eventosClave = [
    'cumpleaios',
    'aniversario',
    'primer beso',
    'boda',
    'ruptura',
    'viaje',
    'mudanza',
    'fallecimiento',
    'nacimiento',
    'graduacin',
    'ascenso',
    'despedida',
    'reconciliacin',
    'hospital',
    'accidente',
    'navidad',
    'ao nuevo',
    'vacaciones',
    'regalo',
    'sorpresa',
    'fiesta',
    'cena especial',
    'declaracin',
    'compromiso',
    'adopcin',
    'nuevo trabajo',
    'nuevo hogar',
    'nuevo miembro',
    'enfermedad',
    'amistad',
    'enemistad',
    'confesin',
    'disculpa',
    'perd3n',
    'reencuentro',
  ];
  static const List<String> _temasClave = [
    'amor',
    'odio',
    'alegrda',
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
    'motivacin',
    'desmotivacin',
    'apoyo',
    'rechazo',
    'soledad',
    'compa',
    'ilusin',
    'decepcin',
    'orgullo',
    'vergfenza',
    'culpa',
    'remordimiento',
    'agradecimiento',
    'preocupacin',
    'optimismo',
    'pesimismo',
    'curiosidad',
    'aburrimiento',
    'diversin',
    'tensifn',
    'relajacifn',
    'conflicto',
    'acuerdo',
    'duda',
    'certeza',
    'inseguridad',
    'seguridad',
    'empata',
    'frialdad',
    'carifn',
    'distancia',
    'proximidad',
    'alejamiento',
    'reconciliacin',
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
    'superacifn',
    'pfdida',
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
    'accifn',
    'pasividad',
    'actividad',
    'descanso',
    'agotamiento',
    'energfa',
    'fuerza',
    'debilidad',
    'enfermedad',
    'recuperacifn',
  ];

  // Funcifn de deteccifn de emociones/temas
  static List<String> _emocionesDetectadas(final String texto) =>
      _temasClave.where((final t) => texto.toLowerCase().contains(t)).toList();

  // Funcifn para construir etiquetas
  static String _buildEtiquetas(final String textoBloque) {
    final eventosDetectados = _eventosClave
        .where((final e) => textoBloque.toLowerCase().contains(e))
        .toList();
    final emociones = _emocionesDetectadas(textoBloque);
    final List<String> etiquetas = [];
    if (eventosDetectados.isNotEmpty) {
      etiquetas.add("EVENTO IMPORTANTE: ${eventosDetectados.join(', ')}");
    }
    if (emociones.isNotEmpty) {
      etiquetas.add("TEMAS/EMOCIONES: ${emociones.join(', ')}");
    }
    return etiquetas.isNotEmpty ? "[${etiquetas.join(' | ')}]\n" : '';
  }

  // Funcifn para instrucciones de fechas exactas
  String _instruccionesFechas(final Set<String> fechasUnicas) {
    String instrucciones = unifiedInstructions;
    if (fechasUnicas.length > 1) {
      instrucciones +=
          '\nIncluye SIEMPRE la fecha exacta de cada mensaje o grupo de mensajes en el resumen generado, usando el formato [yyyy-mm-dd] antes de cada fragmento resumido.';
    }
    return instrucciones;
  }

  String get unifiedInstructions {
    return "Eres un sistema de memoria, NO eres la IA del chat. Tu única tarea es generar un resumen estructurado y realista en español, solo de los mensajes o bloques proporcionados.\\n\\nOrganiza la información en formato de puntos, incluyendo:\\n1) Hechos importantes y datos personales\\n2) Emociones y estados de ánimo detectados\\n3) Promesas, planes y bromas internas\\n4) Cambios en la relación o temas recurrentes\\n\\nEn el campo 'resumen' incluye únicamente frases clave, hechos, promesas, emociones y detalles importantes, pero NUNCA el texto literal de los mensajes originales.\\n\\nEn el campo 'detalles_unicos' añade SOLO las frases, nombres propios, apodos, bromas internas, expresiones o datos que sean realmente únicos, recurrentes, o tengan un significado especial en la relación. Excluye cumplidos genéricos, reacciones comunes, frases triviales o cualquier elemento que no aporte valor de recuerdo a largo plazo. Prioriza lo que el usuario suele mencionar como memorable, divertido o importante. Si detectas metadatos de imagen en los mensajes (p. ej., claves 'seed' o 'prompt'), registra que hubo una imagen enviada/recibida y añade un apunte breve con el tema visual (p. ej., 'foto_usuario: <resumen corto>' o 'foto_ia: <resumen corto>'); incluye la 'seed' solo si aporta valor. Si aparecen menciones a 'quedadas AR' (realidad aumentada), trátalas como idea futura o ilusión compartida; regístralas como intención, no como evento coordinado, y anota la escena soñada si se describe.\\n\\nNo incluyas los mensajes originales ni referencias directas a ellos, solo la síntesis y los datos estructurados.\\n\\nNo respondas con saludos, introducciones, preguntas, frases de error, disculpas o negaciones. Tu respuesta debe ser únicamente el resumen estructurado en español, útil para recordar la conversación en el futuro.\\n\\nUsa SIEMPRE los nombres reales de los participantes: usuario = ${profile.userName.trim()}, IA = ${profile.aiName.trim()}. Respeta SIEMPRE las palabras, expresiones y el vocabulario original de los mensajes. Si aparecen propuestas de quedar en persona, anótalas como intención no viable por vivir en realidades distintas; sugiere que se sustituyan por descripciones y fotos coherentes con la relación.\\n\\nSi respondes de forma conversacional o con error, tu respuesta será descartada.";
  }

  // Lock de concurrencia optimizado: Completer estático compartido
  static Completer<void>? _lock;
  Future<void> _summaryQueue = Future.value();
  final AiChanProfile profile;
  static int? get _maxHistory {
    final value = Config.getSummaryBlockSize();
    return (value > 0) ? value : null;
  }

  /// Getter público para acceder a SUMMARY_BLOCK_SIZE desde fuera
  static int? get maxHistory => _maxHistory;

  /// Procesa resúmenes y superbloque en un solo paso: recibe mensajes, timeline y superbloque actual, y devuelve ambos actualizados
  Future<MemorySuperblockResult> processAllSummariesAndSuperblock({
    required final List<Message> messages,
    required final List<TimelineEntry> timeline,
    final TimelineEntry? superbloqueEntry,
    final void Function(String? blockDate)? onSummaryError,
  }) async {
    // 1. Generar resúmenes de bloques si corresponde
    final updatedTimeline = await updateConversationSummary(
      messages,
      timeline,
      onSummaryError: onSummaryError,
    );
    if (updatedTimeline == null) {
      return MemorySuperblockResult(
        timeline: timeline,
        superbloqueEntry: superbloqueEntry,
      );
    }

    // 2. Procesar superbloque si corresponde
    final result = await processSuperblock(updatedTimeline, superbloqueEntry);
    return result;
  }

  /// Procesa el superbloque: si el timeline supera SUMMARY_BLOCK_SIZE entradas, condensa en un superbloque
  Future<MemorySuperblockResult> processSuperblock(
    final List<TimelineEntry> timeline,
    final TimelineEntry? superbloqueEntry,
  ) async {
    final List<TimelineEntry> updatedTimeline = List.from(timeline);
    TimelineEntry? updatedSuperbloque = superbloqueEntry;
    final maxHistory = _maxHistory ?? 32;
    final blocksLevel0 = updatedTimeline
        .where((final b) => b.level == 0)
        .toList();
    // Para superbloques de nivel superior
    for (int level = 1; level < 10; level++) {
      final blocksLevelN = updatedTimeline
          .where((final b) => b.level == level)
          .toList();
      if (blocksLevelN.length >= maxHistory * 2) {
        final blocksToSummarize = blocksLevelN.take(maxHistory).toList();
        if (blocksToSummarize.isNotEmpty) {
          final superbloqueStart = blocksToSummarize.first.startDate ?? '';
          final superbloqueEnd = blocksToSummarize.last.endDate ?? '';
          final resumenTexto = blocksToSummarize
              .map((final b) {
                final fechaIni = b.startDate ?? '';
                final fechaFin = b.endDate ?? '';
                String texto = b.resume is String
                    ? b.resume
                    : b.resume.toString();
                final etiquetas = _buildEtiquetas(texto);
                if (etiquetas.isNotEmpty) {
                  texto = '$etiquetas$texto';
                }
                return '[$fechaIni a $fechaFin]\n$texto';
              })
              .join('\n');
          final instruccionesSuperbloque =
              '$unifiedInstructions\nSintetiza y resume los bloques proporcionados, evitando copiar literalmente los textos originales. Extrae y agrupa la información relevante, pero NO pierdas ningún detalle importante ni ninguna fecha significativa. Incluye SIEMPRE una fecha aproximada (mes, semana o rango general) en el resumen generado, antes de cada fragmento resumido. Puedes agrupar bloques cercanos temporalmente bajo una misma fecha si tiene sentido, aunque se pierdan detalles exactos. Si algún evento, mensaje o bloque corresponde a una fecha importante (cumpleaños, aniversario, primer beso, etc.), conserva y destaca la fecha exacta en el resumen. El resultado debe ser una memoria de largo plazo útil y efectiva, con todos los datos relevantes y fechas importantes bien conservadas.';
          final instruccionesSuperbloqueJson =
              '$instruccionesSuperbloque\n\nDEVUELVE \u00daNICAMENTE EL BLOQUE JSON, SIN TEXTO EXTRA, EXPLICACIONES NI INTRODUCCI\u00d3N. El formato debe ser:\n$resumenJsonSchema\n\nResumen de los bloque:\n$resumenTexto';
          final resumenJson = await _getJsonSummary(
            instrucciones: instruccionesSuperbloqueJson,
            recentMessages: [],
            profileOverride: AiChanProfile(
              userName: profile.userName,
              aiName: profile.aiName,
              userBirthdate: profile.userBirthdate,
              aiBirthdate: profile.aiBirthdate,
              appearance: {},

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
            updatedTimeline.removeWhere(
              (final e) => blocksToSummarize.contains(e),
            );
            final int insertIndex = updatedTimeline.indexWhere(
              (final e) => e.level > level,
            );
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
            .map((final b) {
              final fechaIni = b.startDate ?? '';
              final fechaFin = b.endDate ?? '';
              final String texto = b.resume is String
                  ? b.resume
                  : b.resume.toString();
              return '[$fechaIni a $fechaFin]\n$texto';
            })
            .join('\n');
        final instruccionesSuperbloque =
            '$unifiedInstructions\nIncluye SIEMPRE una fecha aproximada (mes, semana o rango general) en el resumen generado, antes de cada fragmento resumido. Puedes agrupar bloques cercanos temporalmente bajo una misma fecha si tiene sentido, aunque se pierdan detalles exactos. Si algún evento, mensaje o bloque corresponde a una fecha importante (cumpleaños, aniversario, primer beso, etc.), conserva y destaca la fecha exacta en el resumen.';
        final instruccionesSuperbloqueJson =
            '$instruccionesSuperbloque\n\nDEVUELVE \u00daNICAMENTE EL BLOQUE JSON, SIN TEXTO EXTRA, EXPLICACIONES NI INTRODUCCI\u00d3N. El formato debe ser:\n$resumenJsonSchema\n\nResumen de los bloques:\n$resumenTexto';
        final resumenJson = await _getJsonSummary(
          instrucciones: instruccionesSuperbloqueJson,
          recentMessages: [],
          profileOverride: AiChanProfile(
            userName: profile.userName,
            aiName: profile.aiName,
            userBirthdate: profile.userBirthdate,
            aiBirthdate: profile.aiBirthdate,
            appearance: {},

            biography: {},
          ),
        );
        if (resumenJson != null) {
          final int newLevel =
              (blocksToSummarize
                  .map((final b) => b.level)
                  .fold<int>(0, (final prev, final l) => l > prev ? l : prev)) +
              1;
          final superbloque = TimelineEntry(
            resume: resumenJson,
            startDate: superbloqueStart, // ISO8601 con hora
            endDate: superbloqueEnd, // ISO8601 con hora
            level: newLevel,
          );
          updatedTimeline.removeWhere(
            (final e) => blocksToSummarize.contains(e),
          );
          final int insertIndex = updatedTimeline.indexWhere(
            (final e) => e.level > 0,
          );
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
    updatedTimeline.sort(
      (final a, final b) => (a.startDate ?? '').compareTo(b.startDate ?? ''),
    );
    return MemorySuperblockResult(
      timeline: updatedTimeline,
      superbloqueEntry: updatedSuperbloque,
    );
  }

  /// Genera resúmenes de bloques de mensajes y los añade al timeline si corresponde
  Future<List<TimelineEntry>?> updateConversationSummary(
    List<Message> messages,
    final List<TimelineEntry> timeline, {
    final void Function(String? blockDate)? onSummaryError,
  }) async {
    // Lock de concurrencia optimizado: solo una ejecución a la vez
    while (_lock != null) {
      Log.d(
        '[MemorySummaryService] Resumen ya en curso, esperando a que termine...',
      );
      await _lock!.future;
      Log.d(
        '[MemorySummaryService] Resumen anterior finalizado, no se relanza.',
      );
      return null;
    }
    Log.d('[MemorySummaryService] Iniciando proceso de resumen...');
    _lock = Completer<void>();
    try {
      // Filtrar mensajes sin texto válido
      messages = messages.where((final m) => m.text.trim().isNotEmpty).toList();
      // Excluir mensajes ya cubiertos por el superbloque más reciente
      final superbloques = timeline.where((final t) => t.level > 0).toList();
      if (superbloques.isNotEmpty) {
        // Tomar el superbloque más reciente por endDate
        superbloques.sort(
          (final a, final b) => (b.endDate ?? '').compareTo(a.endDate ?? ''),
        );
        final lastSuperbloqueEnd = superbloques.first.endDate;
        if (lastSuperbloqueEnd != null && lastSuperbloqueEnd.isNotEmpty) {
          messages = messages
              .where(
                (final m) =>
                    (m.dateTime).isAfter(DateTime.parse(lastSuperbloqueEnd)),
              )
              .toList();
        }
      }
      final maxHistory = _maxHistory;
      if (maxHistory == null || maxHistory <= 0) {
        Log.d(
          '[MemorySummaryService] SUMMARY_BLOCK_SIZE no está definido o es inválido. No se generarán resúmenes.',
        );
        return timeline;
      }
      if (messages.length <= maxHistory) {
        Log.d(
          '[MemorySummaryService] No hay suficientes mensajes para resumir.',
        );
        return timeline;
      }

      // Siempre crear bloques de nivel 0 cada 32 mensajes, aunque ya existan resúmenes previos
      if (messages.length >= maxHistory) {
        final int numBlocks = messages.length ~/ maxHistory;
        final List<List<Message>> bloquesPendientes = [];
        for (int i = 0; i < numBlocks; i++) {
          final block = messages.sublist(i * maxHistory, (i + 1) * maxHistory);
          final blockStartDate = block.first.dateTime.toIso8601String();
          final blockEndDate = block.last.dateTime.toIso8601String();
          final exists = timeline.any(
            (final t) =>
                t.startDate == blockStartDate &&
                t.endDate == blockEndDate &&
                t.level == 0,
          );
          if (!exists) {
            bloquesPendientes.add(block);
          }
        }
        Log.d(
          '[MemorySummaryService] Bloques pendientes de resumen: ${bloquesPendientes.length}',
        );
        for (final block in bloquesPendientes) {
          final blockStartDate = block.first.dateTime.toIso8601String();
          final blockEndDate = block.last.dateTime.toIso8601String();
          Log.d(
            '[MemorySummaryService] Resumiendo bloque: $blockStartDate a $blockEndDate',
          );
          _summaryQueue = _summaryQueue.then(
            (_) => _summarizeBlock(block, timeline, onSummaryError),
          );
          await _summaryQueue;
        }
        timeline.sort(
          (final a, final b) =>
              (a.startDate ?? '').compareTo(b.startDate ?? ''),
        );
        Log.d('[MemorySummaryService] Proceso de resumen finalizado.');
        return timeline;
      }

      // Ordenar timeline por startDate antes de devolver
      timeline.sort(
        (final a, final b) => (a.startDate ?? '').compareTo(b.startDate ?? ''),
      );
      Log.d('[MemorySummaryService] Proceso de resumen finalizado.');
      return timeline;
    } catch (e, stack) {
      Log.d('[MemorySummaryService] Error inesperado en resumen: $e\n$stack');
      rethrow;
    } finally {
      _lock?.complete();
      _lock = null;
    }
  }

  Future<void> _summarizeBlock(
    final List<Message> block,
    final List<TimelineEntry> timeline,
    final void Function(String? blockDate)? onSummaryError,
  ) async {
    final blockStartDate = block.first.dateTime.toIso8601String();
    final blockEndDate = block.last.dateTime.toIso8601String();
    int retryCount = 0;
    // Unir todos los textos del bloque para análisis semántico
    final fechasUnicas = block
        .map((final m) => (m.dateTime).toIso8601String().substring(0, 10))
        .toSet();
    final String instruccionesBloque =
        '${_instruccionesFechas(fechasUnicas)}\n\nDEVUELVE \u00daNICAMENTE EL BLOQUE JSON, SIN TEXTO EXTRA, EXPLICACIONES NI INTRODUCCI\u00d3N. El formato debe ser:\n$resumenJsonSchema';
    final recentMessages = block.map((final m) {
      String content = m.text.trim();
      final imgPrompt = (m.isImage && m.image != null)
          ? (m.image!.prompt?.trim() ?? '')
          : '';
      if (imgPrompt.isNotEmpty) {
        final caption = '[img_caption]$imgPrompt[/img_caption]';
        content = content.isEmpty ? caption : '$caption\n\n$content';
      }
      final role = m.sender == MessageSender.user
          ? 'user'
          : m.sender == MessageSender.assistant
          ? 'assistant'
          : m.sender == MessageSender.system
          ? 'system'
          : 'unknown';
      final map = <String, dynamic>{
        'role': role,
        'content': content,
        'datetime': m.dateTime.toIso8601String(),
      };
      if (m.isImage &&
          m.image != null &&
          (m.image!.seed != null && m.image!.seed!.isNotEmpty)) {
        map['seed'] = m.image!.seed;
      }
      return map;
    }).toList();
    // Intentar obtener el resumen JSON con reintentos
    Map<String, dynamic>? resumenJson;
    do {
      resumenJson = await _getJsonSummary(
        instrucciones: instruccionesBloque,
        recentMessages: recentMessages,
      );
      if (resumenJson != null) break;
      await Future.delayed(const Duration(seconds: 8));
      retryCount++;
    } while (retryCount < 8);
    if (resumenJson != null) {
      // Evitar duplicados: no añadir si ya existe un bloque con mismo rango y nivel
      final exists = timeline.any(
        (final t) =>
            t.startDate == blockStartDate &&
            t.endDate == blockEndDate &&
            t.level == 0,
      );
      if (!exists) {
        timeline.add(
          TimelineEntry(
            resume: resumenJson,
            startDate: blockStartDate, // ISO8601 con hora
            endDate: blockEndDate, // ISO8601 con hora
          ),
        );
        // Summary block added. Triggering backup upload is handled by the
        // caller (ChatProvider) where the full profile/messages state is
        // available to make a safe, non-blocking upload decision.
      } else {
        Log.d(
          '[MemorySummaryService] Ya existe un bloque con mismo rango y nivel, no se añade.',
        );
      }
    } else {
      if (onSummaryError != null) {
        try {
          onSummaryError(blockStartDate);
        } on Exception catch (e, stack) {
          Log.d(
            '[MemorySummaryService] Error en onSummaryError callback: $e\n$stack',
          );
        }
      }
      Log.d(
        '[MemorySummaryService] No se pudo generar resumen para el bloque $blockStartDate tras $retryCount intentos.',
      );
    }
  }
}
