import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:ai_chan/models/ai_chan_profile.dart';
import 'package:ai_chan/services/ai_service.dart';
import '../models/system_prompt.dart';
import '../models/message.dart' as chat_model;
import '../models/timeline_entry.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class MemorySuperblockResult {
  final List<TimelineEntry> timeline;
  final TimelineEntry? superbloqueEntry;
  MemorySuperblockResult({required this.timeline, required this.superbloqueEntry});
}

class MemorySummaryService {
  // Prompt unificado para todos los niveles de resumen
  String get unifiedInstructions {
    return "Eres un sistema de memoria, NO eres la IA del chat. Tu única tarea es generar un resumen estructurado y realista en español, solo de los mensajes o bloques proporcionados. Organiza la información en formato de puntos, incluyendo: 1) Hechos importantes y datos personales, 2) Emociones y estados de ánimo detectados, 3) Promesas, planes y bromas internas, 4) Cambios en la relación o temas recurrentes. No respondas con saludos, introducciones, preguntas, ni frases como 'NO_REPLY', 'Lo siento', disculpas, negaciones o mensajes de error. Tu respuesta debe ser únicamente el resumen estructurado en español, útil para recordar la conversación en el futuro. Usa SIEMPRE los nombres reales de los participantes: usuario = ${profile.userName.trim()}, IA = ${profile.aiName.trim()}. No uses pronombres genéricos ni cambies el vocabulario original. Respeta SIEMPRE las palabras y expresiones de los mensajes. Si respondes de forma conversacional o con error, tu respuesta será descartada.";
  }

  // Lock de concurrencia optimizado: Completer estático compartido
  static Completer<void>? _lock;
  Future<void> _summaryQueue = Future.value();
  static const String superblockModel = 'gemini-2.5-flash';
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
                return "[$fechaIni a $fechaFin]\n${b.resume}";
              })
              .join('\n');
          final systemPromptProfile = AiChanProfile(
            userName: profile.userName,
            aiName: profile.aiName,
            userBirthday: profile.userBirthday,
            aiBirthday: profile.aiBirthday,
            appearance: profile.appearance,
            timeline: [],
            personality: {},
            biography: {},
          );
          final instruccionesSuperbloque =
              "$unifiedInstructions\nIncluye SIEMPRE una fecha aproximada (mes, semana o rango general) en el resumen generado, antes de cada fragmento resumido. Puedes agrupar bloques cercanos temporalmente bajo una misma fecha si tiene sentido, aunque se pierdan detalles exactos. Si algún evento, mensaje o bloque corresponde a una fecha importante (cumpleaños, aniversario, primer beso, etc.), conserva y destaca la fecha exacta en el resumen.";
          final systemPrompt = SystemPrompt(
            profile: systemPromptProfile,
            dateTime: DateTime.now(),
            instructions: "$instruccionesSuperbloque\n$resumenTexto",
          );
          final resumenResp = await AIService.sendMessage([], systemPrompt, model: superblockModel);
          final resumen = resumenResp.text;
          if (resumen.trim().isNotEmpty && !resumen.trim().toLowerCase().startsWith('error:')) {
            final int newLevel = level + 1;
            final superbloque = TimelineEntry(
              resume: resumen,
              startDate: superbloqueStart,
              endDate: superbloqueEnd,
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
        // Construir resumenTexto incluyendo fechas de cada bloque
        final resumenTexto = blocksToSummarize
            .map((b) {
              final fechaIni = b.startDate ?? '';
              final fechaFin = b.endDate ?? '';
              return "[$fechaIni a $fechaFin]\n${b.resume}";
            })
            .join('\n');
        // Crear copia del perfil sin timeline
        final systemPromptProfile = AiChanProfile(
          userName: profile.userName,
          aiName: profile.aiName,
          userBirthday: profile.userBirthday,
          aiBirthday: profile.aiBirthday,
          appearance: profile.appearance,
          timeline: [],
          personality: {},
          biography: {},
        );
        // Instrucción adicional para que la IA utilice fechas aproximadas y agrupe bloques
        final instruccionesSuperbloque =
            "$unifiedInstructions\nIncluye SIEMPRE una fecha aproximada (mes, semana o rango general) en el resumen generado, antes de cada fragmento resumido. Puedes agrupar bloques cercanos temporalmente bajo una misma fecha si tiene sentido, aunque se pierdan detalles exactos. Si algún evento, mensaje o bloque corresponde a una fecha importante (cumpleaños, aniversario, primer beso, etc.), conserva y destaca la fecha exacta en el resumen.";
        final systemPrompt = SystemPrompt(
          profile: systemPromptProfile,
          dateTime: DateTime.now(),
          instructions: "$instruccionesSuperbloque\n$resumenTexto",
        );
        final resumenResp = await AIService.sendMessage([], systemPrompt, model: superblockModel);
        final resumen = resumenResp.text;
        if (resumen.trim().isNotEmpty && !resumen.trim().toLowerCase().startsWith('error:')) {
          final int newLevel =
              (blocksToSummarize.map((b) => b.level).fold<int>(0, (prev, l) => l > prev ? l : prev)) + 1;
          final superbloque = TimelineEntry(
            resume: resumen,
            startDate: superbloqueStart,
            endDate: superbloqueEnd,
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
    String summary = '';
    do {
      // Crear copia del perfil sin timeline
      final systemPromptProfile = AiChanProfile(
        userName: profile.userName,
        aiName: profile.aiName,
        userBirthday: profile.userBirthday,
        aiBirthday: profile.aiBirthday,
        appearance: profile.appearance,
        timeline: [],
        personality: {},
        biography: {},
      );
      // Si el bloque contiene mensajes de varios días diferentes, añade instrucción para que se incluyan fechas exactas
      final fechasUnicas = block.map((m) => m.dateTime.toIso8601String().substring(0, 10)).toSet();
      String instruccionesBloque = unifiedInstructions;
      if (fechasUnicas.length > 1) {
        instruccionesBloque +=
            "\nIncluye SIEMPRE la fecha exacta de cada mensaje o grupo de mensajes en el resumen generado, usando el formato [yyyy-mm-dd] antes de cada fragmento resumido.";
      }
      final systemPrompt = SystemPrompt(
        profile: systemPromptProfile,
        dateTime: DateTime.now(),
        recentMessages: block
            .map(
              (m) => {
                "role": m.sender == chat_model.MessageSender.user ? "user" : "assistant",
                "content": m.text,
                "datetime": m.dateTime.toIso8601String(),
              },
            )
            .toList(),
        instructions: instruccionesBloque,
      );
      final response = await AIService.sendMessage([], systemPrompt, model: superblockModel);
      summary = response.text;
      final lowerSummary = summary.trim().toLowerCase();

      if (summary.contains('rate_limit_exceeded') || summary.contains('Rate limit')) {
        await Future.delayed(Duration(seconds: _extractWaitSeconds(summary)));
      } else if (summary.contains('Gemini') && summary.contains('500') && summary.contains('internal error')) {
        await Future.delayed(const Duration(seconds: 5));
      } else if (lowerSummary.isEmpty ||
          lowerSummary.contains('lo siento') ||
          lowerSummary.contains('no puedo continuar') ||
          lowerSummary.contains('no puedo ayudarte con eso') ||
          lowerSummary.contains('no puedo responder a esa solicitud') ||
          lowerSummary.contains('no puedo procesar esa petición') ||
          lowerSummary.contains('error al conectar con la IA') ||
          lowerSummary.startsWith('error:')) {
        await Future.delayed(const Duration(seconds: 8));
      } else {
        break;
      }
      retryCount++;
    } while (retryCount < 8);
    final trimmedSummary = summary.trim();
    if (trimmedSummary.isNotEmpty && trimmedSummary != '[NO_REPLY]') {
      // Evitar duplicados: no añadir si ya existe un bloque con mismo rango y nivel
      final exists = timeline.any((t) => t.startDate == blockStartDate && t.endDate == blockEndDate && t.level == 0);
      if (!exists) {
        timeline.add(TimelineEntry(resume: trimmedSummary, startDate: blockStartDate, endDate: blockEndDate, level: 0));
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

  int _extractWaitSeconds(String text) {
    final regex = RegExp(r'try again in ([\d\.]+)s');
    final match = regex.firstMatch(text);
    if (match != null && match.groupCount > 0) {
      return double.tryParse(match.group(1) ?? '10')?.round() ?? 10;
    }
    return 10;
  }
}
