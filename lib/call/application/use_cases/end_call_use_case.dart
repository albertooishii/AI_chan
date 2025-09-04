import 'dart:async';
import 'package:ai_chan/call/domain/entities/voice_call_state.dart';
import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/core/models.dart';

class EndCallUseCase {
  final ICallManager _callManager;

  EndCallUseCase(this._callManager);

  Future<void> execute({
    required ChatProvider chatProvider,
    required VoiceCallState callState,
  }) async {
    try {
      Log.d('🔚 EndCallUseCase: Finalizando llamada', tag: 'END_CALL_USE_CASE');

      // Finalizar llamada
      await _callManager.endCall();

      // Actualizar estado en ChatProvider
      await _updateChatProvider(
        chatProvider: chatProvider,
        callState: callState,
      );

      Log.d(
        '✅ EndCallUseCase: Llamada finalizada exitosamente',
        tag: 'END_CALL_USE_CASE',
      );
    } catch (e) {
      Log.e('❌ Error en EndCallUseCase', tag: 'END_CALL_USE_CASE', error: e);
      rethrow;
    }
  }

  Future<void> _updateChatProvider({
    required ChatProvider chatProvider,
    required VoiceCallState callState,
  }) async {
    try {
      // Determinar tipo de finalización de llamada
      final shouldMarkRejected = callState.forceReject;
      final shouldMarkMissed =
          callState.endReason == CallEndReason.timeout ||
          callState.endReason == CallEndReason.missed;

      if (shouldMarkRejected) {
        await _handleRejectedCall(
          chatProvider: chatProvider,
          callState: callState,
        );
      } else if (shouldMarkMissed) {
        await _handleMissedCall(
          chatProvider: chatProvider,
          callState: callState,
        );
      } else {
        await _handleCompletedCall(
          chatProvider: chatProvider,
          callState: callState,
        );
      }
    } catch (e) {
      Log.e(
        '❌ Error actualizando ChatProvider',
        tag: 'END_CALL_USE_CASE',
        error: e,
      );
    }
  }

  Future<void> _handleRejectedCall({
    required ChatProvider chatProvider,
    required VoiceCallState callState,
  }) async {
    final rejectionText = _getRejectionText(callState.endReason);

    await chatProvider.updateOrAddCallStatusMessage(
      text: rejectionText,
      callStatus: CallStatus.rejected,
      incoming: callState.isIncoming,
    );
  }

  Future<void> _handleMissedCall({
    required ChatProvider chatProvider,
    required VoiceCallState callState,
  }) async {
    await chatProvider.updateOrAddCallStatusMessage(
      text: 'Llamada sin contestar',
      callStatus: CallStatus.missed,
      incoming: callState.isIncoming,
    );
  }

  Future<void> _handleCompletedCall({
    required ChatProvider chatProvider,
    required VoiceCallState callState,
  }) async {
    // Para llamadas completadas, generar resumen si hay contenido
    if (callState.aiText.isNotEmpty || callState.userText.isNotEmpty) {
      // TODO: Implementar generación de resumen de llamada
      Log.d(
        '📝 Generando resumen de llamada completada',
        tag: 'END_CALL_USE_CASE',
      );
    }
  }

  String _getRejectionText(CallEndReason? reason) {
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
