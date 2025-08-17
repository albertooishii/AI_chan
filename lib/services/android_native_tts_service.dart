import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidNativeTtsService {
  static const MethodChannel _channel = MethodChannel('ai_chan/native_tts');

  static bool get isAndroid => Platform.isAndroid;

  /// Verifica si el TTS nativo de Android está disponible
  static Future<bool> isNativeTtsAvailable() async {
    if (!isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } catch (e) {
      debugPrint('[AndroidTTS] Error verificando disponibilidad: $e');
      return false;
    }
  }

  /// Obtiene la lista de voces disponibles en el sistema Android
  static Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    if (!isAndroid) return [];

    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getVoices');
      if (result == null) return [];

      return result.map((voice) => Map<String, dynamic>.from(voice)).toList();
    } catch (e) {
      debugPrint('[AndroidTTS] Error obteniendo voces: $e');
      return [];
    }
  }

  /// Obtiene voces filtradas por idioma
  static Future<List<Map<String, dynamic>>> getVoicesForLanguage(String languageCode) async {
    final allVoices = await getAvailableVoices();

    return allVoices.where((voice) {
      final locale = voice['locale'] as String?;
      if (locale == null) return false;

      // Comparar con el código de idioma (ej: 'es' coincide con 'es-ES', 'es-MX', etc.)
      final lang = languageCode.split('-').first.toLowerCase();
      final voiceLang = locale.split('-').first.toLowerCase();

      return voiceLang == lang;
    }).toList();
  }

  /// Sintetiza texto a voz usando el TTS nativo de Android
  static Future<bool> synthesizeText({
    required String text,
    String? voiceName,
    String languageCode = 'es-ES',
    double pitch = 1.0,
    double speechRate = 1.0,
  }) async {
    if (!isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('speak', {
        'text': text,
        'voiceName': voiceName,
        'languageCode': languageCode,
        'pitch': pitch,
        'speechRate': speechRate,
      });

      return result ?? false;
    } catch (e) {
      debugPrint('[AndroidTTS] Error sintetizando texto: $e');
      return false;
    }
  }

  /// Sintetiza texto a archivo de audio
  static Future<String?> synthesizeToFile({
    required String text,
    required String outputPath,
    String? voiceName,
    String languageCode = 'es-ES',
    double pitch = 1.0,
    double speechRate = 1.0,
  }) async {
    if (!isAndroid) return null;

    try {
      final result = await _channel.invokeMethod<String>('synthesizeToFile', {
        'text': text,
        'outputPath': outputPath,
        'voiceName': voiceName,
        'languageCode': languageCode,
        'pitch': pitch,
        'speechRate': speechRate,
      });

      return result;
    } catch (e) {
      debugPrint('[AndroidTTS] Error sintetizando a archivo: $e');
      return null;
    }
  }

  /// Detiene la síntesis actual
  static Future<bool> stop() async {
    if (!isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('stop');
      return result ?? false;
    } catch (e) {
      debugPrint('[AndroidTTS] Error deteniendo síntesis: $e');
      return false;
    }
  }

  /// Verifica si hay voces descargadas para un idioma específico
  static Future<bool> hasLanguageVoices(String languageCode) async {
    final voices = await getVoicesForLanguage(languageCode);
    return voices.isNotEmpty;
  }

  /// Obtiene información sobre voces disponibles para descargar
  static Future<List<Map<String, dynamic>>> getDownloadableLanguages() async {
    if (!isAndroid) return [];

    try {
      final result = await _channel.invokeMethod<List<dynamic>>('getDownloadableLanguages');
      if (result == null) return [];

      return result.map((lang) => Map<String, dynamic>.from(lang)).toList();
    } catch (e) {
      debugPrint('[AndroidTTS] Error obteniendo idiomas descargables: $e');
      return [];
    }
  }

  /// Solicita la descarga de un idioma específico
  static Future<bool> requestLanguageDownload(String languageCode) async {
    if (!isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('requestDownload', {'languageCode': languageCode});

      return result ?? false;
    } catch (e) {
      debugPrint('[AndroidTTS] Error solicitando descarga de idioma: $e');
      return false;
    }
  }

  /// Verifica el estado de descarga de un idioma
  static Future<String> getLanguageDownloadStatus(String languageCode) async {
    if (!isAndroid) return 'not_supported';

    try {
      final result = await _channel.invokeMethod<String>('getDownloadStatus', {'languageCode': languageCode});

      return result ?? 'unknown';
    } catch (e) {
      debugPrint('[AndroidTTS] Error obteniendo estado de descarga: $e');
      return 'error';
    }
  }

  /// Formatea la información de una voz para mostrar
  static String formatVoiceInfo(Map<String, dynamic> voice) {
    final name = voice['name'] as String? ?? 'Sin nombre';
    final locale = voice['locale'] as String? ?? 'Sin idioma';
    final quality = voice['quality'] as String? ?? 'normal';
    final isNetworkRequired = voice['requiresNetworkConnection'] as bool? ?? false;

    final qualityText = quality == 'very_high'
        ? 'Neural'
        : quality == 'high'
        ? 'Alta'
        : 'Normal';
    final networkText = isNetworkRequired ? ' (Red)' : '';

    return '$name - $locale ($qualityText$networkText)';
  }
}
