import 'dart:async';
import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

class HandleIncomingCallUseCase {
  HandleIncomingCallUseCase(this._callManager);
  final ICallManager _callManager;

  Future<void> startRinging() async {
    try {
      Log.d(
        '📞 HandleIncomingCallUseCase: Iniciando ring entrante',
        tag: 'INCOMING_CALL_USE_CASE',
      );
      // En el futuro, el CallManager podría tener métodos específicos para ringtones
      // Por ahora, simplemente manejamos el estado
    } on Exception catch (e) {
      Log.e(
        '❌ Error iniciando ring entrante',
        tag: 'INCOMING_CALL_USE_CASE',
        error: e,
      );
      rethrow;
    }
  }

  Future<void> stopRinging() async {
    try {
      Log.d(
        '⏹️ HandleIncomingCallUseCase: Deteniendo ring entrante',
        tag: 'INCOMING_CALL_USE_CASE',
      );
      // En el futuro, el CallManager podría tener métodos específicos para ringtones
      // Por ahora, simplemente manejamos el estado
    } on Exception catch (e) {
      Log.e(
        '❌ Error deteniendo ring entrante',
        tag: 'INCOMING_CALL_USE_CASE',
        error: e,
      );
      rethrow;
    }
  }

  Future<void> acceptCall() async {
    try {
      Log.d(
        '✅ HandleIncomingCallUseCase: Aceptando llamada entrante',
        tag: 'INCOMING_CALL_USE_CASE',
      );
      await _callManager.answerIncomingCall();
    } on Exception catch (e) {
      Log.e(
        '❌ Error aceptando llamada entrante',
        tag: 'INCOMING_CALL_USE_CASE',
        error: e,
      );
      rethrow;
    }
  }

  Future<void> rejectCall() async {
    try {
      Log.d(
        '❌ HandleIncomingCallUseCase: Rechazando llamada entrante',
        tag: 'INCOMING_CALL_USE_CASE',
      );
      await _callManager.rejectIncomingCall();
    } on Exception catch (e) {
      Log.e(
        '❌ Error rechazando llamada entrante',
        tag: 'INCOMING_CALL_USE_CASE',
        error: e,
      );
      rethrow;
    }
  }
}
