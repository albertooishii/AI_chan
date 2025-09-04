import 'dart:async';
import 'package:ai_chan/call/infrastructure/adapters/call_controller.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

class ManageAudioUseCase {
  final CallController _callController;
  final StreamController<double> _audioLevelController =
      StreamController<double>.broadcast();

  ManageAudioUseCase(this._callController);

  Stream<double> get audioLevelStream => _audioLevelController.stream;

  Future<void> initialize() async {
    try {
      Log.d(
        '🎵 ManageAudioUseCase: Inicializando gestión de audio',
        tag: 'AUDIO_USE_CASE',
      );
      // TODO: Configurar streams de audio level del controller
      // Por ahora simularemos con valores estáticos
    } catch (e) {
      Log.e(
        '❌ Error inicializando gestión de audio',
        tag: 'AUDIO_USE_CASE',
        error: e,
      );
      rethrow;
    }
  }

  void setMuted(bool muted) {
    try {
      _callController.setMuted(muted);
      Log.d(
        '🎤 Audio ${muted ? "silenciado" : "activado"}',
        tag: 'AUDIO_USE_CASE',
      );
    } catch (e) {
      Log.e('❌ Error configurando mute', tag: 'AUDIO_USE_CASE', error: e);
    }
  }

  void updateAudioLevel(double level) {
    _audioLevelController.add(level);
  }

  void dispose() {
    Log.d('🗑️ ManageAudioUseCase: Disposing', tag: 'AUDIO_USE_CASE');
    _audioLevelController.close();
  }
}
