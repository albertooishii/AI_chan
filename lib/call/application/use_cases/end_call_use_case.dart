import 'dart:async';
import 'package:ai_chan/call/domain/entities/voice_call_state.dart';
import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/core/domain/interfaces/i_call_to_chat_communication_service.dart'; // ✅ Bounded Context Abstraction

class EndCallUseCase {
  EndCallUseCase(this._callManager, this._chatCommunicationService);

  final ICallManager _callManager;
  final ICallToChatCommunicationService _chatCommunicationService;

  Future<void> execute({required final VoiceCallState callState}) async {
    try {
      Log.d('🔚 EndCallUseCase: Finalizando llamada', tag: 'END_CALL_USE_CASE');

      // Finalizar llamada
      await _callManager.endCall();

      // Actualizar estado en ChatProvider
      await _updateChatCommunication(
        callState: callState,
      ); // ✅ Bounded Context Abstraction

      Log.d(
        '✅ EndCallUseCase: Llamada finalizada exitosamente',
        tag: 'END_CALL_USE_CASE',
      );
    } on Exception catch (e) {
      Log.e('❌ Error en EndCallUseCase', tag: 'END_CALL_USE_CASE', error: e);
      rethrow;
    }
  }

  Future<void> _updateChatCommunication({
    required final VoiceCallState callState,
  }) async {
    // ✅ Bounded Context Abstraction - usar interfaz en lugar de dependencia directa
    try {
      // Determinar tipo de finalización de llamada
      final shouldMarkRejected = callState.forceReject;
      final shouldMarkMissed =
          callState.endReason == CallEndReason.timeout ||
          callState.endReason == CallEndReason.missed;

      if (shouldMarkRejected) {
        await _handleRejectedCall(callState: callState);
      } else if (shouldMarkMissed) {
        await _handleMissedCall(callState: callState);
      } else {
        await _handleCompletedCall(callState: callState);
      }
    } on Exception catch (e) {
      Log.e(
        '❌ Error actualizando comunicación con chat',
        tag: 'END_CALL_USE_CASE',
        error: e,
      ); // ✅ Bounded Context Abstraction
    }
  }

  Future<void> _handleRejectedCall({
    required final VoiceCallState callState,
  }) async {
    // ✅ Bounded Context Abstraction - usar interfaz
    final rejectionText = _getRejectionText(callState.endReason);
    await _chatCommunicationService.sendCallMessage(
      text: rejectionText,
      callType: 'rejected',
    ); // ✅ Bounded Context Abstraction
  }

  Future<void> _handleMissedCall({
    required final VoiceCallState callState,
  }) async {
    // ✅ Bounded Context Abstraction
    await _chatCommunicationService.sendCallMessage(
      text: 'Llamada sin contestar',
      callType: 'missed',
    ); // ✅ Bounded Context Abstraction
  }

  Future<void> _handleCompletedCall({
    required final VoiceCallState callState,
  }) async {
    // ✅ Bounded Context Abstraction: Type safety en ETAPA 2
    // Para llamadas completadas, generar resumen si hay contenido
    if (callState.aiText.isNotEmpty || callState.userText.isNotEmpty) {
      // TODO: Implementar generación de resumen de llamada
      Log.d(
        '📝 Generando resumen de llamada completada',
        tag: 'END_CALL_USE_CASE',
      );
    }
  }

  String _getRejectionText(final CallEndReason? reason) {
    switch (reason) {
      case CallEndReason.timeout:
        return 'Llamada no contestada (timeout)';
      case CallEndReason.rejected:
        return 'Llamada rechazada';
      case CallEndReason.error:
        return 'Llamada terminada por error';
      default:
        return 'Llamada rechazada';
    }
  }
}
