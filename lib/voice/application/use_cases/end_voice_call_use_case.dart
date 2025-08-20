import 'package:ai_chan/voice/domain/domain.dart';

/// Caso de uso para finalizar una llamada de voz activa
class EndVoiceCallUseCase {
  final IVoiceCallRepository _repository;
  final IRealtimeVoiceClient _realtimeClient;

  const EndVoiceCallUseCase(this._repository, this._realtimeClient);

  /// Finaliza una llamada de voz activa
  Future<VoiceCall> execute(String callId) async {
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
    final finishedCall = VoiceCallOrchestrationService.finishCall(call);

    // Actualizar en repositorio
    await _repository.updateCall(finishedCall);

    return finishedCall;
  }

  /// Finaliza una llamada por razón de fallo
  Future<VoiceCall> executeWithFailure(String callId, String reason) async {
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
    final failedCall = VoiceCallOrchestrationService.markCallAsFailed(
      call,
      reason,
    );

    // Actualizar en repositorio
    await _repository.updateCall(failedCall);

    return failedCall;
  }

  /// Cancela una llamada activa
  Future<VoiceCall> executeCancel(String callId) async {
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
    final cancelledCall = VoiceCallOrchestrationService.cancelCall(call);

    // Actualizar en repositorio
    await _repository.updateCall(cancelledCall);

    return cancelledCall;
  }
}
