import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:ai_chan/shared/infrastructure/utils/image/image_utils.dart'
    as image_utils;
import 'package:ai_chan/shared.dart';

/// Servicio simple para persistir audio (base64 -> fichero) y cargarlo.
class AudioPersistenceService {
  AudioPersistenceService._();

  static final AudioPersistenceService _instance = AudioPersistenceService._();
  static AudioPersistenceService get instance => _instance;

  /// Guarda un base64 de audio en disco y devuelve el fileName relativo o null.
  /// Usa la misma carpeta de `ImagePersistenceService` para simplicidad.
  Future<String?> saveBase64Audio(
    final String base64, {
    final String prefix = 'audio',
  }) async {
    try {
      if (base64.trim().isEmpty) return null;
      // Reuse image_utils.saveBase64ImageToFile which handles data URIs and decoding.
      final result = await image_utils.saveBase64ImageToFile(
        base64,
        prefix: prefix,
      );
      if (result == null) {
        Log.w('[AudioPersistence] saveBase64Audio returned null');
        return null;
      }
      Log.d('[AudioPersistence] Saved audio as $result');
      return result;
    } on Exception catch (e) {
      Log.w('[AudioPersistence] Error saving audio: $e');
      return null;
    }
  }

  /// Carga un fichero de audio (por fileName relativo) y devuelve bytes or null.
  Future<List<int>?> loadAudioAsBytes(final String fileName) async {
    try {
      final dir = await image_utils.getLocalImageDir();
      final file = File(p.join(dir.path, fileName));
      if (!file.existsSync()) return null;
      return await file.readAsBytes();
    } on Exception catch (e) {
      Log.w('[AudioPersistence] Error loading audio $fileName: $e');
      return null;
    }
  }

  /// Carga un fichero de audio y devuelve su base64 (sin data URI) o null.
  Future<String?> loadAudioAsBase64(final String fileName) async {
    final bytes = await loadAudioAsBytes(fileName);
    if (bytes == null) return null;
    return base64Encode(bytes);
  }
}
