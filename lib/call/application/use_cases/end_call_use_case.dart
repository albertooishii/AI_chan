import 'dart:async';
import 'package:ai_chan/call/domain/entities/voice_call_state.dart';
import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:ai_chan/call/infrastructure/adapters/call_controller.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/core/models.dart';

class EndCallUseCase {
  final CallController _callController;

  EndCallUseCase(this._callController);

  Future<void> execute({
    required ChatProvider chatProvider,
    required VoiceCallState callState,
  }) async {
    try {
      Log.d('🔚 EndCallUseCase: Finalizando llamada', tag: 'END_CALL_USE_CASE');

      // Silenciar micrófono inmediatamente
      _callController.setMuted(true);

      // Reproducir tono de colgado
      try {
        unawaited(_callController.playHangupTone());
      } catch (e) {
        Log.d(
          '⚠️ Error reproduciendo tono de colgado: $e',
          tag: 'END_CALL_USE_CASE',
        );
      }

      // Determinar si hubo conversación real
      final hadConversation =
          _callController.userSpokeFlag ||
          _callController.firstAudioReceivedFlag;
      final placeholderIndex = chatProvider.pendingIncomingCallMsgIndex;

      // Lógica de categorización de llamada
      final shouldMarkRejected = callState.forceReject;
      final shouldMarkMissed = !shouldMarkRejected && !hadConversation;

      // Detener controller
      await _stopCallController();

      // Actualizar estado en ChatProvider
      await _updateChatProvider(
        chatProvider: chatProvider,
        callState: callState,
        markRejected: shouldMarkRejected,
        markMissed: shouldMarkMissed,
        placeholderIndex: placeholderIndex,
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

  Future<void> _stopCallController() async {
    try {
      await _callController
          .stop(keepFxPlaying: true)
          .timeout(const Duration(milliseconds: 800));
    } catch (e) {
      Log.d('⚠️ Error deteniendo controller: $e', tag: 'END_CALL_USE_CASE');
    }
  }

  Future<void> _updateChatProvider({
    required ChatProvider chatProvider,
    required VoiceCallState callState,
    required bool markRejected,
    required bool markMissed,
    required int? placeholderIndex,
  }) async {
    try {
      if (markRejected) {
        await _handleRejectedCall(
          chatProvider: chatProvider,
          callState: callState,
          placeholderIndex: placeholderIndex,
        );
      } else if (markMissed) {
        await _handleMissedCall(
          chatProvider: chatProvider,
          callState: callState,
          placeholderIndex: placeholderIndex,
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
    required int? placeholderIndex,
  }) async {
    final rejectionText = _getRejectionText(callState.endReason);

    if (placeholderIndex != null) {
      chatProvider.rejectIncomingCallPlaceholder(
        index: placeholderIndex,
        text: rejectionText,
      );
    } else {
      await chatProvider.updateOrAddCallStatusMessage(
        text: rejectionText,
        callStatus: CallStatus.rejected,
        incoming: callState.isIncoming,
        placeholderIndex: placeholderIndex,
      );
    }
  }

  Future<void> _handleMissedCall({
    required ChatProvider chatProvider,
    required VoiceCallState callState,
    required int? placeholderIndex,
  }) async {
    if (placeholderIndex != null) {
      chatProvider.rejectIncomingCallPlaceholder(
        index: placeholderIndex,
        text: 'Llamada sin contestar',
      );
    } else {
      await chatProvider.updateOrAddCallStatusMessage(
        text: 'Llamada sin contestar',
        callStatus: CallStatus.missed,
        incoming: callState.isIncoming,
        placeholderIndex: placeholderIndex,
      );
    }
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
