import 'dart:async';
import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Implementación temporal del AudioManager para compilación
/// TODO: Implementar lógica real de audio
class AudioManagerImpl implements IAudioManager {
  final StreamController<double> _audioLevelController =
      StreamController<double>.broadcast();
  bool _isMuted = false;

  @override
  void setMuted(final bool muted) {
    Log.d('🎤 AudioManagerImpl: Set muted $muted', tag: 'AUDIO_MANAGER');
    _isMuted = muted;
  }

  @override
  bool get isMuted => _isMuted;

  @override
  Stream<double> get audioLevelStream => _audioLevelController.stream;

  @override
  void updateAudioLevel(final double level) {
    _audioLevelController.add(level);
  }

  @override
  Future<void> initialize() async {
    Log.d('🎵 AudioManagerImpl: Inicializando', tag: 'AUDIO_MANAGER');
    // TODO: Implementar inicialización real de audio

    // Simular nivel de audio bajo
    Timer.periodic(const Duration(milliseconds: 100), (final Timer timer) {
      if (!_audioLevelController.isClosed) {
        updateAudioLevel(0.1);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    Log.d('🗑️ AudioManagerImpl: Disposing', tag: 'AUDIO_MANAGER');
    _audioLevelController.close();
  }
}
