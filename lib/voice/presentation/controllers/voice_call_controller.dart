import 'package:flutter/foundation.dart';
import '../../domain/interfaces/i_tone_service.dart';
import '../../application/services/microphone_amplitude_service.dart';

/// 🎯 Controller simple para llamadas de voz con tonos
/// Versión simplificada enfocada en UI de llamadas básicas
class VoiceCallController extends ChangeNotifier {
  VoiceCallController(this._toneService);
  final IToneService _toneService;

  // Estado de la llamada
  bool _isInCall = false;
  bool _isMuted = false;
  double _volume = 0.7;

  // Getters para la UI
  bool get isInCall => _isInCall;
  bool get isMuted => _isMuted;
  double get volume => _volume;

  String get statusText {
    if (_isInCall) {
      return _isMuted
          ? '🔇 En llamada (silenciado)'
          : '📞 Hablando con AI-chan';
    }
    return '📱 Presiona para llamar a AI-chan';
  }

  /// 📞 Iniciar llamada de voz
  Future<void> startCall() async {
    try {
      // Reproducir tono de llamada
      await _toneService.playRingtone(durationMs: 2000);

      // Simular conexión
      await Future.delayed(const Duration(milliseconds: 2000));

      _isInCall = true;
      _isMuted = false;

      // Iniciar simulación de amplitud del micrófono
      MicrophoneAmplitudeService.instance.startListening();

      notifyListeners();

      debugPrint('🎯 VoiceCallController: Llamada iniciada');
    } on Exception catch (e) {
      debugPrint('❌ Error iniciando llamada: $e');
      // En caso de error, reproducir tono de colgado
      await _toneService.playHangupTone();
    }
  }

  /// 📵 Terminar llamada
  Future<void> endCall() async {
    try {
      // Detener simulación de amplitud
      MicrophoneAmplitudeService.instance.stopListening();

      // Reproducir tono de colgado
      await _toneService.playHangupTone();

      _isInCall = false;
      _isMuted = false;
      notifyListeners();

      debugPrint('🎯 VoiceCallController: Llamada terminada');
    } on Exception catch (e) {
      debugPrint('❌ Error terminando llamada: $e');
    }
  }

  /// 🔇 Toggle mute/unmute
  void toggleMute() {
    _isMuted = !_isMuted;

    // Manejar amplitud del micrófono según estado de mute
    if (_isInCall) {
      if (_isMuted) {
        MicrophoneAmplitudeService.instance.stopListening();
      } else {
        MicrophoneAmplitudeService.instance.startListening();
      }
    }

    notifyListeners();
    debugPrint('🎯 VoiceCallController: Mute ${_isMuted ? 'ON' : 'OFF'}');
  }

  /// 🔊 Ajustar volumen
  void setVolume(final double newVolume) {
    _volume = newVolume.clamp(0.0, 1.0);
    notifyListeners();
    debugPrint('🎯 VoiceCallController: Volumen = ${(_volume * 100).round()}%');
  }

  /// 🧪 Probar tonos cyberpunk
  Future<void> testTones() async {
    try {
      debugPrint('🎯 VoiceCallController: Probando tono de llamada...');
      await _toneService.playRingtone(durationMs: 1500);

      await Future.delayed(const Duration(milliseconds: 500));

      debugPrint('🎯 VoiceCallController: Probando tono de colgado...');
      await _toneService.playHangupTone();

      debugPrint('✅ VoiceCallController: Prueba de tonos completada');
    } on Exception catch (e) {
      debugPrint('❌ Error probando tonos: $e');
    }
  }

  /// 🛑 Detener cualquier audio
  Future<void> stopAudio() async {
    try {
      await _toneService.stop();
    } on Exception catch (e) {
      debugPrint('❌ Error deteniendo audio: $e');
    }
  }

  @override
  void dispose() {
    // Limpiar recursos si hay llamada activa
    if (_isInCall) {
      stopAudio();
    }
    super.dispose();
  }
}
