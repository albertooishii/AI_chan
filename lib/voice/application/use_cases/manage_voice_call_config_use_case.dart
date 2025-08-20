import 'package:ai_chan/voice/domain/domain.dart';

/// Caso de uso para gestionar la configuración de llamadas
class ManageVoiceCallConfigUseCase {
  final IVoiceCallRepository _repository;
  final IRealtimeVoiceClient _realtimeClient;

  const ManageVoiceCallConfigUseCase(this._repository, this._realtimeClient);

  /// Actualiza la voz durante una llamada activa
  Future<void> executeUpdateVoice({
    required String callId,
    required String newVoice,
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
  Future<VoiceCall> executePause(String callId) async {
    // Obtener llamada actual
    final call = await _repository.getCall(callId);
    if (call == null) {
      throw ArgumentError('Call with ID $callId not found');
    }

    // Pausar usando servicio de dominio
    final pausedCall = VoiceCallOrchestrationService.pauseCall(call);

    // Actualizar en repositorio
    await _repository.updateCall(pausedCall);

    return pausedCall;
  }

  /// Reanuda una llamada pausada
  Future<VoiceCall> executeResume(String callId) async {
    // Obtener llamada actual
    final call = await _repository.getCall(callId);
    if (call == null) {
      throw ArgumentError('Call with ID $callId not found');
    }

    // Reanudar usando servicio de dominio
    final resumedCall = VoiceCallOrchestrationService.resumeCall(call);

    // Actualizar en repositorio
    await _repository.updateCall(resumedCall);

    return resumedCall;
  }

  /// Actualiza metadatos de una llamada
  Future<VoiceCall> executeUpdateMetadata({
    required String callId,
    required Map<String, dynamic> metadata,
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
  Future<void> executeDelete(String callId) async {
    await _repository.deleteCall(callId);
  }

  /// Elimina todo el historial de llamadas
  Future<void> executeDeleteAll() async {
    await _repository.deleteAllCalls();
  }
}
