import 'package:ai_chan/voice/domain/domain.dart';
import 'package:ai_chan/core/models.dart';

/// Caso de uso para obtener el historial de llamadas
class GetVoiceCallHistoryUseCase {
  final IVoiceCallRepository _repository;

  const GetVoiceCallHistoryUseCase(this._repository);

  /// Obtiene todas las llamadas
  Future<List<VoiceCall>> execute() async {
    return await _repository.getAllCalls();
  }

  /// Obtiene una llamada específica por ID
  Future<VoiceCall?> executeById(String callId) async {
    return await _repository.getCall(callId);
  }

  /// Obtiene llamadas por rango de fechas
  Future<List<VoiceCall>> executeByDateRange({
    required DateTime from,
    required DateTime to,
  }) async {
    return await _repository.getCallsByDateRange(from, to);
  }

  /// Obtiene llamadas filtradas por proveedor
  Future<List<VoiceCall>> executeByProvider(VoiceProvider provider) async {
    final allCalls = await _repository.getAllCalls();
    return allCalls.where((call) => call.provider == provider).toList();
  }

  /// Obtiene llamadas filtradas por estado
  Future<List<VoiceCall>> executeByStatus(CallStatus status) async {
    final allCalls = await _repository.getAllCalls();
    return allCalls.where((call) => call.status == status).toList();
  }

  /// Obtiene estadísticas de una llamada
  Future<Map<String, dynamic>?> executeGetStats(String callId) async {
    final call = await _repository.getCall(callId);
    if (call == null) return null;

    return VoiceCallOrchestrationService.calculateCallStats(call);
  }

  /// Obtiene estadísticas agregadas de todas las llamadas
  Future<Map<String, dynamic>> executeGetGlobalStats() async {
    final allCalls = await _repository.getAllCalls();

    if (allCalls.isEmpty) {
      return {
        'totalCalls': 0,
        'totalDuration': Duration.zero,
        'completedCalls': 0,
        'failedCalls': 0,
        'cancelledCalls': 0,
        'averageDuration': Duration.zero,
        'totalMessages': 0,
      };
    }

    final completedCalls = allCalls
        .where((c) => c.status == CallStatus.completed)
        .length;
    final failedCalls = allCalls
        .where((c) => c.status == CallStatus.failed)
        .length;
    final cancelledCalls = allCalls
        .where((c) => c.status == CallStatus.canceled)
        .length;

    final totalDuration = allCalls.fold<Duration>(
      Duration.zero,
      (sum, call) => sum + call.duration,
    );

    final averageDuration = Duration(
      milliseconds: totalDuration.inMilliseconds ~/ allCalls.length,
    );

    final totalMessages = allCalls.fold<int>(
      0,
      (sum, call) => sum + call.messages.length,
    );

    return {
      'totalCalls': allCalls.length,
      'totalDuration': totalDuration,
      'completedCalls': completedCalls,
      'failedCalls': failedCalls,
      'cancelledCalls': cancelledCalls,
      'averageDuration': averageDuration,
      'totalMessages': totalMessages,
    };
  }
}
