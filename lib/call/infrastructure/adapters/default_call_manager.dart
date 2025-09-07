import 'dart:async';
import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';
import 'package:flutter/foundation.dart';

/// Implementación del gestor de llamadas
/// Maneja el ciclo de vida de las llamadas
class DefaultCallManager implements ICallManager {
  bool _isCallActive = false;
  final StreamController<bool> _callStateController =
      StreamController<bool>.broadcast();

  @override
  bool get isCallActive => _isCallActive;

  @override
  Stream<bool> get callStateStream => _callStateController.stream;

  @override
  Future<void> startCall() async {
    if (_isCallActive) {
      debugPrint('[DefaultCallManager] Call already active');
      return;
    }

    _isCallActive = true;
    _callStateController.add(true);
    debugPrint('[DefaultCallManager] Call started');
  }

  @override
  Future<void> endCall() async {
    if (!_isCallActive) {
      debugPrint('[DefaultCallManager] No active call to end');
      return;
    }

    _isCallActive = false;
    _callStateController.add(false);
    debugPrint('[DefaultCallManager] Call ended');
  }

  @override
  Future<void> answerIncomingCall() async {
    debugPrint('[DefaultCallManager] Answering incoming call');
    await startCall();
  }

  @override
  Future<void> rejectIncomingCall() async {
    debugPrint('[DefaultCallManager] Rejecting incoming call');
    // No cambiamos el estado ya que rechazamos la llamada
  }

  @override
  void dispose() {
    _callStateController.close();
    debugPrint('[DefaultCallManager] Disposed');
  }
}
