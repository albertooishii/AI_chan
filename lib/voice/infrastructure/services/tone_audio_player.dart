import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 🎯 Servicio simple para reproducir tonos WAV generados
class ToneAudioPlayer {
  factory ToneAudioPlayer() => _instance;
  ToneAudioPlayer._internal();
  static final ToneAudioPlayer _instance = ToneAudioPlayer._internal();

  final AudioPlayer _player = AudioPlayer();

  /// 🔊 Reproducir datos WAV directamente
  Future<void> playWavData(final Uint8List wavData) async {
    try {
      debugPrint(
        '🎵 ToneAudioPlayer: Reproduciendo ${wavData.length} bytes de audio WAV',
      );

      // Crear archivo temporal para el audio
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/temp_tone_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      // Escribir datos WAV al archivo temporal
      await tempFile.writeAsBytes(wavData);

      // Reproducir desde archivo
      await _player.play(DeviceFileSource(tempFile.path));

      debugPrint('✅ ToneAudioPlayer: Audio reproducido correctamente');

      // Programar limpieza del archivo temporal después de un tiempo
      Future.delayed(const Duration(seconds: 10), () async {
        try {
          if (tempFile.existsSync()) {
            await tempFile.delete();
            debugPrint('🧹 ToneAudioPlayer: Archivo temporal limpiado');
          }
        } on Exception catch (e) {
          debugPrint(
            '⚠️ ToneAudioPlayer: Error limpiando archivo temporal: $e',
          );
        }
      });
    } on Exception catch (e) {
      debugPrint('❌ ToneAudioPlayer: Error reproduciendo audio: $e');
      throw Exception('Error reproduciendo audio: $e');
    }
  }

  /// 🛑 Detener reproducción actual
  Future<void> stop() async {
    try {
      await _player.stop();
      debugPrint('🛑 ToneAudioPlayer: Reproducción detenida');
    } on Exception catch (e) {
      debugPrint('⚠️ ToneAudioPlayer: Error deteniendo reproducción: $e');
    }
  }

  /// 🔧 Verificar si está disponible
  bool get isAvailable => true;

  /// 🧹 Limpiar recursos
  void dispose() {
    _player.dispose();
  }
}
