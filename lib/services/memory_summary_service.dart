import 'package:flutter/foundation.dart';
import 'package:ai_chan/models/ai_chan_profile.dart';
import 'package:ai_chan/services/ai_service.dart';
import '../models/message.dart' as chat_model;
import '../models/timeline_entry.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class MemorySuperblockResult {
  final List<TimelineEntry> timeline;
  final TimelineEntry? superbloqueEntry;
  MemorySuperblockResult({required this.timeline, required this.superbloqueEntry});
}

class MemorySummaryService {
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
    if (updatedTimeline.length >= maxHistory) {
      final oldestBlock = updatedTimeline.removeAt(0);
      if (updatedSuperbloque == null) {
        final resumenResp = await AIService.sendMessage(
          [
            {
              "role": "system",
              "content":
                  "Eres un sistema de memoria. Resume el siguiente bloque de conversación en formato de puntos, conservando SIEMPRE los datos clave (nombres, fechas, lugares, apodos, etc.). No respondas como IA del chat.",
            },
            {"role": "system", "content": oldestBlock.resume},
          ],
          '',
          model: superblockModel,
        );
        final resumen = resumenResp.text;
        updatedSuperbloque = TimelineEntry(
          date: 'SUPERBLOCK_${DateTime.now().toIso8601String()}',
          resume: resumen.length > 4000 ? resumen.substring(0, 4000) : resumen,
        );
      } else {
        final resumenResp = await AIService.sendMessage(
          [
            {
              "role": "system",
              "content":
                  "Eres un sistema de memoria. Añade el siguiente bloque al resumen existente, condensando y conservando SIEMPRE los datos clave (nombres, fechas, lugares, apodos, etc.). No respondas como IA del chat.",
            },
            {"role": "system", "content": updatedSuperbloque.resume},
            {"role": "system", "content": oldestBlock.resume},
          ],
          '',
          model: superblockModel,
        );
        final resumen = resumenResp.text;
        updatedSuperbloque = TimelineEntry(
          date: updatedSuperbloque.date,
          resume: resumen.length > 4000 ? resumen.substring(0, 4000) : resumen,
        );
      }
      updatedTimeline.removeWhere((e) => e.date == updatedSuperbloque!.date);
      updatedTimeline.add(updatedSuperbloque);
    }
    return MemorySuperblockResult(timeline: updatedTimeline, superbloqueEntry: updatedSuperbloque);
  }

  /// Genera resúmenes de bloques de mensajes y los añade al timeline si corresponde
  Future<List<TimelineEntry>> updateConversationSummary(
    List<chat_model.Message> messages,
    List<TimelineEntry> timeline, {
    void Function(String? blockDate)? onSummaryError,
  }) async {
    // Filtrar mensajes sin texto válido
    messages = messages.where((m) => m.text.trim().isNotEmpty).toList();
    final maxHistory = _maxHistory;
    if (maxHistory == null || maxHistory <= 0) {
      debugPrint(
        '[MemorySummaryService] SUMMARY_BLOCK_SIZE no está definido o es inválido. No se generarán resúmenes.',
      );
      return timeline;
    }
    if (messages.length <= maxHistory) return timeline;

    final bloquesPendientes = <int>[];
    for (int i = 0; i + maxHistory <= messages.length; i += maxHistory) {
      final block = messages.sublist(i, i + maxHistory);
      if (block.isEmpty) continue;
      final blockDate = block.first.dateTime.toIso8601String();
      if (timeline.any((t) => t.date == blockDate)) continue;
      bloquesPendientes.add(i);
    }
    for (final i in bloquesPendientes) {
      final block = messages.sublist(i, i + maxHistory);
      await _summarizeBlock(block, timeline, onSummaryError);
    }
    return timeline;
  }

  Future<void> _summarizeBlock(
    List<chat_model.Message> block,
    List<TimelineEntry> timeline,
    void Function(String? blockDate)? onSummaryError,
  ) async {
    final blockDate = block.first.dateTime.toIso8601String();
    String userName = profile.userName.trim();
    String aiName = profile.aiName.trim();

    List<Map<String, dynamic>> buildPrompt() {
      // Enviar los mensajes del bloque como mensajes normales, sin campo 'type'
      return [
        {
          "role": "system",
          "content":
              "Eres un sistema de memoria, NO eres la IA del chat. Tu única tarea es generar un resumen estructurado y realista en español, SOLO de los mensajes de este bloque (no acumules ni expandas resúmenes previos). Ignora cualquier contexto conversacional, nunca respondas como si fueras la IA del chat, ni interactúes con los participantes. Organiza la información en varios puntos claros: 1) Hechos importantes y datos personales, 2) Emociones y estados de ánimo detectados, 3) Promesas, planes y bromas internas, 4) Cambios en la relación o temas recurrentes. Nunca respondas con frases como 'NO_REPLY', 'Lo siento', disculpas, negaciones, ni mensajes de error. Solo responde con el resumen estructurado solicitado. Evita saludos, introducciones o encabezados innecesarios. Tu respuesta debe ser únicamente el resumen estructurado en español, útil para recordar la conversación en el futuro. Si respondes de forma conversacional, tu respuesta será descartada y no se guardará en la memoria. IMPORTANTE: Usa SIEMPRE los nombres reales de los participantes en el resumen. El usuario se llama: $userName. La IA se llama: $aiName. En los mensajes, 'user' corresponde a $userName y 'assistant' corresponde a $aiName. No uses 'el hombre', 'la mujer', 'él', 'ella', ni pronombres genéricos. Reemplaza por los nombres reales en cada punto del resumen.",
        },
        {
          "role": "system",
          "content":
              "A continuación se presentan los mensajes del bloque. Recuerda: NO estás participando en la conversación, solo debes resumir en formato de puntos. En los mensajes, 'user' es $userName y 'assistant' es $aiName.",
        },
        ...block.map(
          (m) => {"role": m.sender == chat_model.MessageSender.user ? "user" : "assistant", "content": m.text},
        ),
        {
          "role": "system",
          "content":
              "Repite: Eres un sistema de memoria, NO eres la IA del chat. Tu única tarea es generar el resumen estructurado de la conversación en español, solo en formato de puntos. Si respondes de forma conversacional o con error, tu respuesta será descartada. Recuerda conservar y repetir los datos clave en cada nivel de resumen. Usa SIEMPRE los nombres reales: usuario = $userName, IA = $aiName.",
        },
      ];
    }

    int retryCount = 0;
    String summary = '';
    do {
      final summaryPrompt = buildPrompt();
      final promptText = summaryPrompt.where((e) => e['role'] == 'system').map((e) => e['content']).join('\n');
      final payload = block
          .map((m) => {"role": m.sender == chat_model.MessageSender.user ? "user" : "assistant", "content": m.text})
          .toList();

      final response = await AIService.sendMessage(payload, promptText, model: superblockModel);
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
          summary.contains('Error al conectar con la IA') ||
          summary.contains('"error":')) {
        await Future.delayed(const Duration(seconds: 8));
      } else {
        break;
      }
      retryCount++;
    } while (retryCount < 8);
    final trimmedSummary = summary.trim();
    if (trimmedSummary.isNotEmpty && trimmedSummary != '[NO_REPLY]') {
      timeline.add(
        TimelineEntry(
          date: blockDate,
          resume: trimmedSummary.length > 4000 ? trimmedSummary.substring(0, 4000) : trimmedSummary,
        ),
      );
    } else {
      if (onSummaryError != null) {
        try {
          onSummaryError(blockDate);
        } catch (e, stack) {
          debugPrint('[MemorySummaryService] Error en onSummaryError callback: $e\n$stack');
        }
      }
      debugPrint(
        '[MemorySummaryService] No se pudo generar resumen para el bloque $blockDate tras $retryCount intentos.',
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
