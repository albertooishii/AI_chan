import 'dart:async';
import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Implementación temporal del CallManager para compilación
/// TODO: Implementar lógica real de llamadas
class CallManagerImpl implements ICallManager {
  final StreamController<bool> _callStateController =
      StreamController<bool>.broadcast();
  bool _isCallActive = false;

  @override
  Future<void> startCall() async {
    Log.d('📞 CallManagerImpl: Iniciando llamada', tag: 'CALL_MANAGER');
    _isCallActive = true;
    _callStateController.add(_isCallActive);
  }

  @override
  Future<void> endCall() async {
    Log.d('📞 CallManagerImpl: Finalizando llamada', tag: 'CALL_MANAGER');
    _isCallActive = false;
    _callStateController.add(_isCallActive);
  }

  @override
  Future<void> answerIncomingCall() async {
    Log.d(
      '📞 CallManagerImpl: Respondiendo llamada entrante',
      tag: 'CALL_MANAGER',
    );
    _isCallActive = true;
    _callStateController.add(_isCallActive);
  }

  @override
  Future<void> rejectIncomingCall() async {
    Log.d(
      '📞 CallManagerImpl: Rechazando llamada entrante',
      tag: 'CALL_MANAGER',
    );
    _isCallActive = false;
    _callStateController.add(_isCallActive);
  }

  @override
  bool get isCallActive => _isCallActive;

  @override
  Stream<bool> get callStateStream => _callStateController.stream;

  @override
  void dispose() {
    Log.d('🗑️ CallManagerImpl: Disposing', tag: 'CALL_MANAGER');
    _callStateController.close();
  }
}
