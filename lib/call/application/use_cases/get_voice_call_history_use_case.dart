import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';
import 'package:ai_chan/call/domain/models/call.dart';
import 'package:ai_chan/call/domain/models/call_provider.dart';
import 'package:ai_chan/call/domain/services/call_service.dart';
import 'package:ai_chan/core/models.dart';

/// Caso de uso para obtener el historial de llamadas
class GetCallHistoryUseCase {
  const GetCallHistoryUseCase(this._repository);
  final ICallRepository _repository;

  /// Obtiene todas las llamadas
  Future<List<Call>> execute() async {
    return await _repository.getAllCalls();
  }

  /// Obtiene una llamada específica por ID
  Future<Call?> executeById(final String callId) async {
    return await _repository.getCall(callId);
  }

  /// Obtiene llamadas por rango de fechas
  Future<List<Call>> executeByDateRange({
    required final DateTime from,
    required final DateTime to,
  }) async {
    return await _repository.getCallsByDateRange(from, to);
  }

  /// Obtiene llamadas filtradas por proveedor
  Future<List<Call>> executeByProvider(final CallProvider provider) async {
    final allCalls = await _repository.getAllCalls();
    return allCalls.where((final call) => call.provider == provider).toList();
  }

  /// Obtiene llamadas filtradas por estado
  Future<List<Call>> executeByStatus(final CallStatus status) async {
    final allCalls = await _repository.getAllCalls();
    return allCalls.where((final call) => call.status == status).toList();
  }

  /// Obtiene estadísticas de una llamada
  Future<Map<String, dynamic>?> executeGetStats(final String callId) async {
    final call = await _repository.getCall(callId);
    if (call == null) return null;

    return CallOrchestrationService.calculateCallStats(call);
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
        .where((final c) => c.status == CallStatus.completed)
        .length;
    final failedCalls = allCalls
        .where((final c) => c.status == CallStatus.failed)
        .length;
    final cancelledCalls = allCalls
        .where((final c) => c.status == CallStatus.canceled)
        .length;

    final totalDuration = allCalls.fold<Duration>(
      Duration.zero,
      (final sum, final call) => sum + call.duration,
    );

    final averageDuration = Duration(
      milliseconds: totalDuration.inMilliseconds ~/ allCalls.length,
    );

    final totalMessages = allCalls.fold<int>(
      0,
      (final sum, final call) => sum + call.messages.length,
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
