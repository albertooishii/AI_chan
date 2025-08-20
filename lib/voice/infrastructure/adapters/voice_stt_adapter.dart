import 'dart:typed_data';

import 'package:ai_chan/core/interfaces/i_stt_service.dart';
import 'package:ai_chan/voice/domain/interfaces/voice_interfaces.dart';

/// Adaptador que convierte ISttService a IVoiceSttService
class VoiceSttAdapter implements IVoiceSttService {
  final ISttService _sttService;

  const VoiceSttAdapter(this._sttService);

  @override
  Future<String?> transcribeFromBytes(
    Uint8List audioData, {
    String languageCode = 'es-ES',
    Map<String, dynamic>? options,
  }) async {
    // El ISttService actual requiere un archivo, así que necesitamos crear uno temporal
    // En una implementación real, podríamos crear una extensión que soporte bytes directamente
    throw UnimplementedError(
      'transcribeFromBytes requires file-based implementation',
    );
  }

  @override
  Future<String?> transcribeFromFile(
    String audioFilePath, {
    String languageCode = 'es-ES',
    Map<String, dynamic>? options,
  }) async {
    return await _sttService.transcribeAudio(audioFilePath);
  }

  @override
  bool get isAvailable => true;

  @override
  Future<List<String>> getSupportedLanguages() async {
    // Lista básica de idiomas soportados por Google STT
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
