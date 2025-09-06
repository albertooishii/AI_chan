import 'dart:async';
import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

class ManageAudioUseCase {
  ManageAudioUseCase(this._audioManager);
  final IAudioManager _audioManager;

  Stream<double> get audioLevelStream => _audioManager.audioLevelStream;

  Future<void> initialize() async {
    try {
      Log.d(
        '🎵 ManageAudioUseCase: Inicializando gestión de audio',
        tag: 'AUDIO_USE_CASE',
      );
      await _audioManager.initialize();
    } on Exception catch (e) {
      Log.e(
        '❌ Error inicializando gestión de audio',
        tag: 'AUDIO_USE_CASE',
        error: e,
      );
      rethrow;
    }
  }

  void setMuted(final bool muted) {
    try {
      _audioManager.setMuted(muted);
      Log.d(
        '🎤 Audio ${muted ? "silenciado" : "activado"}',
        tag: 'AUDIO_USE_CASE',
      );
    } on Exception catch (e) {
      Log.e('❌ Error configurando mute', tag: 'AUDIO_USE_CASE', error: e);
    }
  }

  bool get isMuted => _audioManager.isMuted;

  void updateAudioLevel(final double level) {
    _audioManager.updateAudioLevel(level);
  }

  void dispose() {
    Log.d('🗑️ ManageAudioUseCase: Disposing', tag: 'AUDIO_USE_CASE');
    _audioManager.dispose();
  }
}
