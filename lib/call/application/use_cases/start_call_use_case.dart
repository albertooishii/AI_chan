import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/call/domain/entities/voice_call_state.dart';
import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

class StartCallUseCase {
  StartCallUseCase(this._callManager);
  final ICallManager _callManager;

  Future<void> execute({
    required final bool isIncoming,
    required final VoidCallback onCallStarted,
    required final Function(CallEndReason) onCallEnded,
  }) async {
    try {
      Log.d(
        '🚀 StartCallUseCase: Iniciando llamada',
        tag: 'START_CALL_USE_CASE',
      );

      // Escuchar cambios de estado
      _callManager.callStateStream.listen((final isActive) {
        if (isActive) {
          onCallStarted();
        } else {
          onCallEnded(CallEndReason.hangup);
        }
      });

      if (isIncoming) {
        await _callManager.answerIncomingCall();
      } else {
        await _callManager.startCall();
      }

      Log.d(
        '✅ StartCallUseCase: Llamada iniciada exitosamente',
        tag: 'START_CALL_USE_CASE',
      );
    } on Exception catch (e) {
      Log.e(
        '❌ Error en StartCallUseCase',
        tag: 'START_CALL_USE_CASE',
        error: e,
      );
      onCallEnded(CallEndReason.error);
      rethrow;
    }
  }
}
