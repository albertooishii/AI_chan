import 'dart:io';
import 'dart:typed_data';

import 'package:ai_chan/core/interfaces/tts_service.dart';
import 'package:ai_chan/voice/domain/interfaces/voice_interfaces.dart';

/// Adaptador que convierte ITtsService a IVoiceTtsService
class VoiceTtsAdapter implements IVoiceTtsService {
  final ITtsService _ttsService;

  const VoiceTtsAdapter(this._ttsService);

  @override
  Future<String?> synthesizeToFile({
    required String text,
    String voice = 'sage',
    String languageCode = 'es-ES',
    Map<String, dynamic>? options,
  }) async {
    return await _ttsService.synthesizeToFile(
      text: text,
      options: {'voice': voice, 'languageCode': languageCode, ...?options},
    );
  }

  @override
  Future<Uint8List?> synthesizeToBytes({
    required String text,
    String voice = 'sage',
    String languageCode = 'es-ES',
    Map<String, dynamic>? options,
  }) async {
    final filePath = await synthesizeToFile(
      text: text,
      voice: voice,
      languageCode: languageCode,
      options: options,
    );

    if (filePath == null) return null;

    try {
      final file = File(filePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        // Opcional: eliminar archivo temporal después de leer
        try {
          await file.delete();
        } catch (_) {}
        return Uint8List.fromList(bytes);
      }
    } catch (_) {}

    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    return await _ttsService.getAvailableVoices();
  }

  @override
  bool get isAvailable => true;

  @override
  Future<List<String>> getSupportedLanguages() async {
    // Lista básica de idiomas soportados por los servicios TTS
    return [
      'es-ES',
      'es-MX',
      'es-AR',
      'en-US',
      'en-GB',
      'fr-FR',
      'de-DE',
      'it-IT',
      'pt-BR',
      'ja-JP',
      'ko-KR',
      'zh-CN',
    ];
  }
}
