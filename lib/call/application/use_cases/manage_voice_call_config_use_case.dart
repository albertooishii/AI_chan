import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';
import 'package:ai_chan/call/domain/models/call.dart';
import 'package:ai_chan/call/domain/services/call_service.dart';

/// Caso de uso para gestionar la configuración de llamadas
class ManageCallConfigUseCase {
  const ManageCallConfigUseCase(this._repository, this._realtimeClient);
  final ICallRepository _repository;
  final IRealtimeCallClient _realtimeClient;

  /// Actualiza la voz durante una llamada activa
  Future<void> executeUpdateVoice({
    required final String callId,
    required final String newVoice,
  }) async {
    // Verificar que la llamada existe y está activa
    final call = await _repository.getCall(callId);
    if (call == null) {
      throw ArgumentError('Call with ID $callId not found');
    }

    if (!call.isActive) {
      throw StateError('Call is not active');
    }

    // Actualizar voz en el cliente realtime
    if (_realtimeClient.isConnected) {
      _realtimeClient.updateVoice(newVoice);
    }

    // Actualizar llamada con nueva voz
    final updatedCall = call.copyWith(voice: newVoice);
    await _repository.updateCall(updatedCall);
  }

  /// Pausa una llamada activa
  Future<Call> executePause(final String callId) async {
    // Obtener llamada actual
    final call = await _repository.getCall(callId);
    if (call == null) {
      throw ArgumentError('Call with ID $callId not found');
    }

    // Pausar usando servicio de dominio
    final pausedCall = CallOrchestrationService.pauseCall(call);

    // Actualizar en repositorio
    await _repository.updateCall(pausedCall);

    return pausedCall;
  }

  /// Reanuda una llamada pausada
  Future<Call> executeResume(final String callId) async {
    // Obtener llamada actual
    final call = await _repository.getCall(callId);
    if (call == null) {
      throw ArgumentError('Call with ID $callId not found');
    }

    // Reanudar usando servicio de dominio
    final resumedCall = CallOrchestrationService.resumeCall(call);

    // Actualizar en repositorio
    await _repository.updateCall(resumedCall);

    return resumedCall;
  }

  /// Actualiza metadatos de una llamada
  Future<Call> executeUpdateMetadata({
    required final String callId,
    required final Map<String, dynamic> metadata,
  }) async {
    // Obtener llamada actual
    final call = await _repository.getCall(callId);
    if (call == null) {
      throw ArgumentError('Call with ID $callId not found');
    }

    // Combinar metadatos existentes con nuevos
    final updatedMetadata = {...?call.metadata, ...metadata};

    // Actualizar llamada
    final updatedCall = call.copyWith(metadata: updatedMetadata);
    await _repository.updateCall(updatedCall);

    return updatedCall;
  }

  /// Elimina una llamada del historial
  Future<void> executeDelete(final String callId) async {
    await _repository.deleteCall(callId);
  }

  /// Elimina todo el historial de llamadas
  Future<void> executeDeleteAll() async {
    await _repository.deleteAllCalls();
  }
}
