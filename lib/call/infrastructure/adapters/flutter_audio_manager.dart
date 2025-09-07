import 'dart:async';
import 'package:ai_chan/call/domain/interfaces/call_interfaces.dart';
import 'package:flutter/foundation.dart';

/// Implementación del gestor de audio para Flutter
/// Maneja el estado de audio en llamadas
class FlutterAudioManager implements IAudioManager {
  bool _isMuted = false;
  final StreamController<double> _audioLevelController = StreamController<double>.broadcast();

  @override
  bool get isMuted => _isMuted;

  @override
  Stream<double> get audioLevelStream => _audioLevelController.stream;

  @override
  void setMuted(final bool muted) {
    _isMuted = muted;
    debugPrint('[FlutterAudioManager] Muted: $muted');
  }

  @override
  void updateAudioLevel(final double level) {
    _audioLevelController.add(level.clamp(0.0, 1.0));
  }

  @override
  Future<void> initialize() async {
    debugPrint('[FlutterAudioManager] Initialized');
    // TODO: Inicializar servicios de audio reales
  }

  @override
  void dispose() {
    _audioLevelController.close();
    debugPrint('[FlutterAudioManager] Disposed');
  }
}
