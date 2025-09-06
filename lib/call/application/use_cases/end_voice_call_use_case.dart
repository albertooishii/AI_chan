import 'package:ai_chan/call/domain/domain.dart';

/// Caso de uso para finalizar una llamada de voz activa
class EndCallUseCase {
  const EndCallUseCase(this._repository, this._realtimeClient);
  final ICallRepository _repository;
  final IRealtimeCallClient _realtimeClient;

  /// Finaliza una llamada de voz activa
  Future<Call> execute(final String callId) async {
    // Obtener llamada actual
    final call = await _repository.getCall(callId);
    if (call == null) {
      throw ArgumentError('Call with ID $callId not found');
    }

    if (!call.isActive) {
      throw StateError('Call is not active and cannot be ended');
    }

    // Desconectar cliente realtime
    await _realtimeClient.disconnect();

    // Finalizar llamada usando servicio de dominio
    final finishedCall = CallOrchestrationService.finishCall(call);

    // Actualizar en repositorio
    await _repository.updateCall(finishedCall);

    return finishedCall;
  }

  /// Finaliza una llamada por razón de fallo
  Future<Call> executeWithFailure(
    final String callId,
    final String reason,
  ) async {
    // Obtener llamada actual
    final call = await _repository.getCall(callId);
    if (call == null) {
      throw ArgumentError('Call with ID $callId not found');
    }

    // Desconectar cliente si está conectado
    try {
      if (_realtimeClient.isConnected) {
        await _realtimeClient.disconnect();
      }
    } catch (e) {
      // Ignorar errores de desconexión en caso de fallo
    }

    // Marcar como fallida usando servicio de dominio
    final failedCall = CallOrchestrationService.markCallAsFailed(call, reason);

    // Actualizar en repositorio
    await _repository.updateCall(failedCall);

    return failedCall;
  }

  /// Cancela una llamada activa
  Future<Call> executeCancel(final String callId) async {
    // Obtener llamada actual
    final call = await _repository.getCall(callId);
    if (call == null) {
      throw ArgumentError('Call with ID $callId not found');
    }

    if (call.isCompleted) {
      throw StateError('Call is already completed and cannot be cancelled');
    }

    // Desconectar cliente
    await _realtimeClient.disconnect();

    // Cancelar llamada usando servicio de dominio
    final cancelledCall = CallOrchestrationService.cancelCall(call);

    // Actualizar en repositorio
    await _repository.updateCall(cancelledCall);

    return cancelledCall;
  }
}
