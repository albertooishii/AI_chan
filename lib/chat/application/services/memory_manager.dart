import 'package:ai_chan/core/services/memory_summary_service.dart';
import 'package:ai_chan/core/models.dart';

class MemoryProcessingResult {
  final List<TimelineEntry> timeline;
  final TimelineEntry? superbloqueEntry;

  MemoryProcessingResult({required this.timeline, this.superbloqueEntry});
}

/// MemoryManager centraliza llamadas al servicio de resumen/memoria.
/// Esto permite testear y desacoplar la lógica que produce el timeline
/// y el superbloque del `ChatProvider`.
class MemoryManager {
  final AiChanProfile profile;

  MemoryManager({required this.profile});

  /// Procesa los mensajes y devuelve los cambios en timeline y superbloque.
  Future<MemoryProcessingResult> processAllSummariesAndSuperblock({
    required List<Message> messages,
    required List<TimelineEntry> timeline,
    TimelineEntry? superbloqueEntry,
  }) async {
    final memoryService = MemorySummaryService(profile: profile);
    final result = await memoryService.processAllSummariesAndSuperblock(
      messages: messages,
      timeline: timeline,
      superbloqueEntry: superbloqueEntry,
    );
    return MemoryProcessingResult(timeline: result.timeline, superbloqueEntry: result.superbloqueEntry);
  }
}
