import 'dart:async';
import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';
import 'package:ai_chan/call/infrastructure/adapters/call_controller.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Implementación de IAudioManager usando CallController
class AudioManagerAdapter implements IAudioManager {
  AudioManagerAdapter(this._callController);
  final CallController _callController;
  final StreamController<double> _audioLevelController =
      StreamController<double>.broadcast();

  @override
  void setMuted(final bool muted) {
    try {
      _callController.setMuted(muted);
      Log.d(
        '🎤 Audio ${muted ? "silenciado" : "activado"}',
        tag: 'AUDIO_MANAGER',
      );
    } catch (e) {
      Log.e('❌ Error configurando mute', tag: 'AUDIO_MANAGER', error: e);
      rethrow;
    }
  }

  @override
  bool get isMuted {
    // Por ahora devolvemos un estado fijo
    // En el futuro podríamos agregar un getter público al CallController
    return false;
  }

  @override
  Stream<double> get audioLevelStream => _audioLevelController.stream;

  @override
  void updateAudioLevel(final double level) {
    _audioLevelController.add(level);
  }

  @override
  Future<void> initialize() async {
    try {
      Log.d(
        '🎵 AudioManagerAdapter: Inicializando gestión de audio',
        tag: 'AUDIO_MANAGER',
      );
      // Aquí podríamos configurar listeners del CallController si fuera necesario
    } catch (e) {
      Log.e(
        '❌ Error inicializando gestión de audio',
        tag: 'AUDIO_MANAGER',
        error: e,
      );
      rethrow;
    }
  }

  @override
  void dispose() {
    Log.d('🗑️ AudioManagerAdapter: Disposing', tag: 'AUDIO_MANAGER');
    _audioLevelController.close();
  }
}

/// Implementación de ICallManager usando CallController
class CallManagerAdapter implements ICallManager {
  CallManagerAdapter(this._callController);
  final CallController _callController;
  final StreamController<bool> _callStateController =
      StreamController<bool>.broadcast();

  @override
  Future<void> startCall() async {
    try {
      Log.d('📞 Iniciando llamada', tag: 'CALL_MANAGER');
      // El CallController usa startContinuousCall, necesitamos crear un wrapper simplificado
      // Por ahora, solo marcamos como activa la llamada
      _callStateController.add(true);
    } catch (e) {
      Log.e('❌ Error iniciando llamada', tag: 'CALL_MANAGER', error: e);
      rethrow;
    }
  }

  @override
  Future<void> endCall() async {
    try {
      Log.d('📞 Finalizando llamada', tag: 'CALL_MANAGER');
      await _callController.stop();
      _callStateController.add(false);
    } catch (e) {
      Log.e('❌ Error finalizando llamada', tag: 'CALL_MANAGER', error: e);
      rethrow;
    }
  }

  @override
  Future<void> answerIncomingCall() async {
    try {
      Log.d('📞 Respondiendo llamada entrante', tag: 'CALL_MANAGER');
      // Detener ring y marcar como activa
      await _callController.stopIncomingRing();
      _callStateController.add(true);
    } catch (e) {
      Log.e(
        '❌ Error respondiendo llamada entrante',
        tag: 'CALL_MANAGER',
        error: e,
      );
      rethrow;
    }
  }

  @override
  Future<void> rejectIncomingCall() async {
    try {
      Log.d('📞 Rechazando llamada entrante', tag: 'CALL_MANAGER');
      await _callController.stopIncomingRing();
      await _callController.stop();
      _callStateController.add(false);
    } catch (e) {
      Log.e(
        '❌ Error rechazando llamada entrante',
        tag: 'CALL_MANAGER',
        error: e,
      );
      rethrow;
    }
  }

  @override
  bool get isCallActive {
    // Por ahora devolvemos un estado fijo
    // En el futuro podríamos agregar un getter público al CallController
    return false;
  }

  @override
  Stream<bool> get callStateStream => _callStateController.stream;

  @override
  void dispose() {
    Log.d('🗑️ CallManagerAdapter: Disposing', tag: 'CALL_MANAGER');
    _callStateController.close();
  }
}
