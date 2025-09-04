import 'dart:async';
import 'package:ai_chan/call/infrastructure/adapters/call_controller.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

class HandleIncomingCallUseCase {
  final CallController _callController;

  HandleIncomingCallUseCase(this._callController);

  Future<void> startRinging() async {
    try {
      Log.d(
        '📞 HandleIncomingCallUseCase: Iniciando ring entrante',
        tag: 'INCOMING_CALL_USE_CASE',
      );
      await _callController.startIncomingRing();
    } catch (e) {
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
      await _callController.stopIncomingRing();
    } catch (e) {
      Log.e(
        '❌ Error deteniendo ring entrante',
        tag: 'INCOMING_CALL_USE_CASE',
        error: e,
      );
      rethrow;
    }
  }
}
