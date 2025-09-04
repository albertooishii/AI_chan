import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/call/domain/entities/voice_call_state.dart';
import 'package:ai_chan/call/infrastructure/adapters/call_controller.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

class StartCallUseCase {
  final CallController _callController;

  StartCallUseCase(this._callController);

  Future<void> execute({
    required String systemPrompt,
    required bool isIncoming,
    required Function(String) onTextReceived,
    required Function(String) onUserTranscription,
    required VoidCallback onCallStarted,
    required Function(CallEndReason) onCallEnded,
  }) async {
    try {
      Log.d(
        '🚀 StartCallUseCase: Iniciando llamada',
        tag: 'START_CALL_USE_CASE',
      );

      await _callController.startContinuousCall(
        systemPrompt: systemPrompt,
        onText: (text) {
          onTextReceived(text);

          // Detectar inicio de llamada
          if (text.contains('[start_call]')) {
            onCallStarted();
          }

          // Detectar fin de llamada
          if (text.contains('[end_call]')) {
            onCallEnded(CallEndReason.hangup);
          }
        },
        onUserTranscription: onUserTranscription,
        onHangupReason: (reason) {
          final endReason = _mapHangupReasonToCallEndReason(reason);
          onCallEnded(endReason);
        },
        suppressInitialAiRequest:
            isIncoming, // Para llamadas entrantes, esperar al usuario
        playRingback: !isIncoming, // Solo ringback en llamadas salientes
      );

      Log.d(
        '✅ StartCallUseCase: Llamada iniciada exitosamente',
        tag: 'START_CALL_USE_CASE',
      );
    } catch (e) {
      Log.e(
        '❌ Error en StartCallUseCase',
        tag: 'START_CALL_USE_CASE',
        error: e,
      );
      onCallEnded(CallEndReason.error);
      rethrow;
    }
  }

  CallEndReason _mapHangupReasonToCallEndReason(String reason) {
    switch (reason.toLowerCase()) {
      case 'user_hangup':
      case 'hangup':
        return CallEndReason.hangup;
      case 'timeout':
      case 'no_answer':
        return CallEndReason.timeout;
      case 'rejected':
      case 'reject':
        return CallEndReason.rejected;
      case 'missed':
        return CallEndReason.missed;
      default:
        return CallEndReason.error;
    }
  }
}
