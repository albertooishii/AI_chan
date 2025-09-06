import 'dart:async';
import 'package:ai_chan/call/domain/entities/voice_call_state.dart';
import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/chat/application/controllers/chat_controller.dart'; // ✅ DDD: ETAPA 3 - DDD puro

class EndCallUseCase {
  EndCallUseCase(this._callManager);
  final ICallManager _callManager;

  Future<void> execute({
    required final ChatController chatController, // ✅ DDD: ETAPA 3 - DDD puro
    required final VoiceCallState callState,
  }) async {
    try {
      Log.d('🔚 EndCallUseCase: Finalizando llamada', tag: 'END_CALL_USE_CASE');

      // Finalizar llamada
      await _callManager.endCall();

      // Actualizar estado en ChatProvider
      await _updateChatController(
        chatController: chatController,
        callState: callState,
      ); // ✅ DDD: ETAPA 3

      Log.d(
        '✅ EndCallUseCase: Llamada finalizada exitosamente',
        tag: 'END_CALL_USE_CASE',
      );
    } catch (e) {
      Log.e('❌ Error en EndCallUseCase', tag: 'END_CALL_USE_CASE', error: e);
      rethrow;
    }
  }

  Future<void> _updateChatController({
    required final ChatController chatController, // ✅ DDD: ETAPA 3
    required final VoiceCallState callState,
  }) async {
    // ✅ DDD: ETAPA 3 - usar ChatController directo
    try {
      // Determinar tipo de finalización de llamada
      final shouldMarkRejected = callState.forceReject;
      final shouldMarkMissed =
          callState.endReason == CallEndReason.timeout ||
          callState.endReason == CallEndReason.missed;

      if (shouldMarkRejected) {
        await _handleRejectedCall(
          chatController: chatController,
          callState: callState,
        );
      } else if (shouldMarkMissed) {
        await _handleMissedCall(
          chatController: chatController,
          callState: callState,
        );
      } else {
        await _handleCompletedCall(
          chatController: chatController,
          callState: callState,
        );
      }
    } catch (e) {
      Log.e(
        '❌ Error actualizando ChatController',
        tag: 'END_CALL_USE_CASE',
        error: e,
      ); // ✅ DDD: ETAPA 3
    }
  }

  Future<void> _handleRejectedCall({
    required final ChatController chatController, // ✅ DDD: ETAPA 3
    required final VoiceCallState callState,
  }) async {
    // ✅ DDD: ETAPA 3 - usar ChatController directo
    final rejectionText = _getRejectionText(callState.endReason);
    await chatController.sendMessage(text: rejectionText); // ✅ DDD: ETAPA 3
  }

  Future<void> _handleMissedCall({
    required final ChatController chatController,
    required final VoiceCallState callState,
  }) async {
    // ✅ DDD: ETAPA 3
    // ✅ DDD: ETAPA 3 - usar ChatController directo
    await chatController.sendMessage(
      text: 'Llamada sin contestar',
    ); // ✅ DDD: ETAPA 3
  }

  Future<void> _handleCompletedCall({
    required final ChatController chatController, // ✅ DDD: ETAPA 3
    required final VoiceCallState callState,
  }) async {
    // ✅ DDD: Type safety en ETAPA 2
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
