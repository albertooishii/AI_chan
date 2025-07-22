import 'package:flutter/foundation.dart';
import 'package:ai_chan/models/ai_chan_profile.dart';
import 'package:ai_chan/services/ai_service.dart';

import '../models/message.dart' as chat_model;
import '../models/timeline_entry.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class MemorySummaryService {
  // Prompt extendido para conservar datos clave
  static const String datosClavePrompt =
      "IMPORTANTE: Debes conservar SIEMPRE los nombres de personas, animales, lugares, fechas importantes, apodos, juegos especiales de pareja y cualquier rasgo clave. "
      "Estos datos deben aparecer en todos los resúmenes, aunque se sigan resumiendo. Nunca los pierdas ni los omitas, repítelos si es necesario en cada nivel de resumen.";
  int _extractWaitSeconds(String text) {
    final regex = RegExp(r'try again in ([\d\.]+)s');
    final match = regex.firstMatch(text);
    if (match != null && match.groupCount > 0) {
      return double.tryParse(match.group(1) ?? '10')?.round() ?? 10;
    }
    return 10;
  }

  final String model;
  final AiChanProfile profile;
  static int? get _maxHistory {
    final value = int.tryParse(dotenv.env['SUMMARY_BLOCK_SIZE'] ?? '');
    return (value != null && value > 0) ? value : null;
  }

  MemorySummaryService({required this.model, required this.profile});

  Future<List<TimelineEntry>> generateBlockSummaries(
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
    // Extraer nombres (ya no pueden ser null)
    String userName = profile.userName.trim();
    String aiName = profile.aiName.trim();

    final summaryPrompt = [
      {
        "role": "system",
        "content":
            "Eres un sistema de memoria, NO eres la IA del chat. Tu única tarea es generar un resumen estructurado y realista en español, SOLO de los mensajes de este bloque (no acumules ni expandas resúmenes previos). Ignora cualquier contexto conversacional, nunca respondas como si fueras la IA del chat, ni interactúes con los participantes. Organiza la información en varios puntos claros: 1) Hechos importantes y datos personales, 2) Emociones y estados de ánimo detectados, 3) Promesas, planes y bromas internas, 4) Cambios en la relación o temas recurrentes. Nunca respondas con frases como 'NO_REPLY', 'Lo siento', disculpas, negaciones, ni mensajes de error. Solo responde con el resumen estructurado solicitado. Evita saludos, introducciones o encabezados innecesarios. Tu respuesta debe ser únicamente el resumen estructurado en español, útil para recordar la conversación en el futuro. Si respondes de forma conversacional, tu respuesta será descartada y no se guardará en la memoria. IMPORTANTE: Usa SIEMPRE los nombres reales de los participantes en el resumen. El usuario se llama: $userName. La IA se llama: $aiName. En los mensajes, 'user' corresponde a $userName y 'assistant' corresponde a $aiName. No uses 'el hombre', 'la mujer', 'él', 'ella', ni pronombres genéricos. Reemplaza por los nombres reales en cada punto del resumen. $datosClavePrompt",
      },
      {
        "role": "system",
        "content":
            "A continuación se presentan los mensajes del bloque. Recuerda: NO estás participando en la conversación, solo debes resumir en formato de puntos. En los mensajes, 'user' es $userName y 'assistant' es $aiName.",
      },
      ...block.map(
        (m) => {
          "role": m.sender == chat_model.MessageSender.user
              ? "user"
              : "assistant",
          "content": m.text,
        },
      ),
      {
        "role": "system",
        "content":
            "Repite: Eres un sistema de memoria, NO eres la IA del chat. Tu única tarea es generar el resumen estructurado de la conversación en español, solo en formato de puntos. Si respondes de forma conversacional o con error, tu respuesta será descartada. Recuerda conservar y repetir los datos clave en cada nivel de resumen. Usa SIEMPRE los nombres reales: usuario = $userName, IA = $aiName.",
      },
    ];

    int retryCount = 0;
    String summary = '';
    do {
      final promptText = summaryPrompt
          .where((e) => e['role'] == 'system')
          .map((e) => e['content'])
          .join('\n');
      final response = await AIService.sendMessage(
        block
            .map(
              (m) => {
                "role": m.sender == chat_model.MessageSender.user
                    ? "user"
                    : "assistant",
                "content": m.text,
              },
            )
            .toList(),
        promptText,
        model: model,
      );
      summary = response.text;
      final lowerSummary = summary.trim().toLowerCase();
      if (summary.contains('rate_limit_exceeded') ||
          summary.contains('Rate limit')) {
        await Future.delayed(Duration(seconds: _extractWaitSeconds(summary)));
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
          resume: trimmedSummary.length > 4000
              ? trimmedSummary.substring(0, 4000)
              : trimmedSummary,
        ),
      );
    } else {
      // Notificar a la interfaz si se proporciona callback
      if (onSummaryError != null) {
        try {
          onSummaryError(blockDate);
        } catch (e, stack) {
          debugPrint(
            '[MemorySummaryService] Error en onSummaryError callback: $e\n$stack',
          );
        }
      }
      // Log para depuración
      debugPrint(
        '[MemorySummaryService] No se pudo generar resumen para el bloque $blockDate tras $retryCount intentos.',
      );
      // Ya no se agrega un bloque vacío ni NO_REPLY
    }
  }
}
