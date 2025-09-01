import 'dart:io';
import 'dart:convert';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ai_chan/shared/utils/voice_display_utils.dart';

// NOTE: We are deprecating the native MethodChannel-based Android TTS shim.
// Internally the app now prefers the Dart plugin `flutter_tts`. This file
// preserves the public API used by the app but delegates to FlutterTts when
// possible. Methods that required native-only behaviors (synthesizeToFile)
// will return null and callers should use cloud services or the
// GoogleSpeechService.textToSpeechFile for persisted audio.

class AndroidNativeTtsService {
  static const MethodChannel _channel = MethodChannel('ai_chan/native_tts');

  static bool get isAndroid => Platform.isAndroid;

  static final FlutterTts _flutterTts = FlutterTts();

  /// Verifica si el TTS nativo de Android está disponible
  static Future<bool> isNativeTtsAvailable() async {
    if (!isAndroid) return false;
    try {
      // The Dart plugin is always available when running on Android.
      return true;
    } catch (e) {
      Log.e('[AndroidTTS] Error verificando disponibilidad (flutter_tts): $e');
      return false;
    }
  }

  /// Obtiene la lista de voces disponibles en el sistema Android
  static Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    if (!isAndroid) return [];
    try {
      final voices = await _flutterTts.getVoices;
      if (voices == null) return [];
      return (voices as List<dynamic>)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
    } catch (e) {
      Log.e('[AndroidTTS] Error obteniendo voces (flutter_tts): $e');
      return [];
    }
  }

  /// Obtiene voces filtradas por idioma
  static Future<List<Map<String, dynamic>>> getVoicesForLanguage(
    String languageCode,
  ) async {
    final allVoices = await getAvailableVoices();

    // Normalizar requested code: reemplazar '_' por '-' y pasar a minúsculas
    final requested = languageCode.replaceAll('_', '-').toLowerCase();

    // Primero intentar coincidencia exacta (lang-region) si se proporcionó región
    final requestedParts = requested.split('-');
    if (requestedParts.length >= 2) {
      final exact = allVoices.where((voice) {
        final locale = (voice['locale'] as String?)
            ?.replaceAll('_', '-')
            .toLowerCase();
        if (locale == null) return false;
        return locale == requested;
      }).toList();

      if (exact.isNotEmpty) return exact;
      // Si no hay coincidencias exactas, caemos al emparejamiento por idioma abajo
    }

    // Fallback: comparar solo la parte de idioma (ej: 'es' coincide con 'es-ES', 'es-MX', etc.)
    final lang = requested.split('-').first.toLowerCase();
    return allVoices.where((voice) {
      final locale = (voice['locale'] as String?)
          ?.replaceAll('_', '-')
          .toLowerCase();
      if (locale == null) return false;
      final voiceLang = locale.split('-').first.toLowerCase();
      return voiceLang == lang;
    }).toList();
  }

  /// Filtra la lista completa de voces según códigos de usuario y de AI.
  /// Comportamiento:
  /// - Normaliza '_' a '-' y pasa a minúsculas.
  /// - Si se solicita al menos un código con región, requiere coincidencia exacta de región.
  /// - En caso contrario, permite coincidencia por idioma.
  static Future<List<Map<String, dynamic>>> filterVoicesByTargetCodes(
    List<Map<String, dynamic>> voices,
    List<String> userCodes,
    List<String> aiCodes,
  ) async {
    final all = voices;
    final allLanguageCodes = <String>[];
    for (final c in [...userCodes, ...aiCodes]) {
      if (c.trim().isEmpty) continue;
      allLanguageCodes.add(c.replaceAll('_', '-').toLowerCase());
    }
    if (allLanguageCodes.isEmpty) return all;

    final Set<String> targetCodes = allLanguageCodes.toSet();
    final hasExactRegion = targetCodes.any((t) => t.contains('-'));

    return all.where((voice) {
      final Set<String> voiceLangCodes = {};
      try {
        final languageCodesField = voice['languageCodes'];
        if (languageCodesField is List && languageCodesField.isNotEmpty) {
          for (final lc in languageCodesField.cast<String>()) {
            voiceLangCodes.add(lc.replaceAll('_', '-').toLowerCase());
          }
        }
      } catch (_) {}

      var locale = (voice['locale'] as String?) ?? '';
      locale = locale.replaceAll('_', '-').toLowerCase();

      if (hasExactRegion) {
        final exactTargets = targetCodes.where((t) => t.contains('-')).toSet();
        if (voiceLangCodes.isNotEmpty) {
          if (voiceLangCodes.any((vlc) => exactTargets.contains(vlc))) {
            return true;
          }
        }
        if (locale.isNotEmpty && exactTargets.contains(locale)) return true;
        return false;
      }

      if (voiceLangCodes.isNotEmpty) {
        for (final t in targetCodes) {
          final tLang = t.split('-').first;
          if (voiceLangCodes.any(
            (vlc) => vlc == tLang || vlc.startsWith('$tLang-'),
          )) {
            return true;
          }
        }
      }

      if (locale.isNotEmpty) {
        final vlang = locale.split('-').first;
        for (final t in targetCodes) {
          final tLang = t.split('-').first;
          if (vlang == tLang) return true;
        }
      }

      return false;
    }).toList();
  }

  /// Debug helper: imprime en consola (JSON) las voces que coinciden con el código de idioma
  ///
  /// Uso: AndroidNativeTtsService.dumpVoicesJsonForLanguage('es-ES');
  /// Si `exactOnly` es true, requerirá coincidencia exacta de región (ej. 'es-ES').
  static Future<String> dumpVoicesJsonForLanguage(
    String languageCode, {
    bool exactOnly = false,
  }) async {
    final all = await getAvailableVoices();
    final requested = languageCode.replaceAll('_', '-').toLowerCase();

    List<Map<String, dynamic>> matched;
    if (exactOnly) {
      matched = all.where((voice) {
        final locale = (voice['locale'] as String?)
            ?.replaceAll('_', '-')
            .toLowerCase();
        return locale != null && locale == requested;
      }).toList();
    } else {
      // Reuse existing getVoicesForLanguage behaviour
      matched = await getVoicesForLanguage(languageCode);
    }

    final out = jsonEncode({
      'requested': requested,
      'count': matched.length,
      'voices': matched,
    });
    return out;
  }

  /// Sintetiza texto a voz usando el TTS nativo de Android
  static Future<bool> synthesizeText({
    required String text,
    String? voiceName,
    String languageCode = 'es-ES',
    double pitch = 1.0,
    double speechRate = 0.5,
  }) async {
    if (!isAndroid) return false;
    try {
      await _flutterTts.setLanguage(languageCode);
      if (voiceName != null) await _flutterTts.setVoice({'name': voiceName});
      await _flutterTts.setPitch(pitch);
      // Normalize/clamp speech rate to platform valid range (fallback to a
      // conservative default to avoid accelerated audio on some engines).
      try {
        final normalized = await _normalizeSpeechRate(speechRate);
        await _flutterTts.setSpeechRate(normalized);
        Log.d('[AndroidTTS] using speechRate=$normalized for synthesizeText');
      } catch (e) {
        await _flutterTts.setSpeechRate(speechRate);
      }
      try {
        await _flutterTts.awaitSpeakCompletion(true);
      } catch (_) {}
      final res = await _flutterTts.speak(text);
      return res == 1 || res == '1' || res == null;
    } catch (e) {
      Log.e('[AndroidTTS] Error sintetizando texto (flutter_tts): $e');
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
    double speechRate = 0.5,
  }) async {
    if (!isAndroid) return null;
    try {
      await _flutterTts.setLanguage(languageCode);
      if (voiceName != null) {
        await _flutterTts.setVoice({'name': voiceName, 'locale': languageCode});
      }
      await _flutterTts.setPitch(pitch);
      try {
        final normalized = await _normalizeSpeechRate(speechRate);
        await _flutterTts.setSpeechRate(normalized);
        Log.d('[AndroidTTS] using speechRate=$normalized for synthesizeToFile');
      } catch (e) {
        await _flutterTts.setSpeechRate(speechRate);
      }

      // Ask plugin to await completion so we can verify file
      try {
        await _flutterTts.awaitSynthCompletion(true);
      } catch (_) {}

      final isFullPath = outputPath.startsWith('/');
      final fileName = outputPath;

      final res = await _flutterTts.synthesizeToFile(
        text,
        fileName,
        isFullPath,
      );

      // If plugin wrote to the given path, verify size
      try {
        final f = File(outputPath);
        if (await f.exists()) {
          final len = await f.length();
          if (len > 0) {
            Log.d(
              '[AndroidTTS] synthesizeToFile produced file: $outputPath (size=$len)',
            );
            return outputPath;
          } else {
            Log.e(
              '[AndroidTTS] synthesizeToFile produced zero-length file: $outputPath',
            );
            try {
              await f.delete();
            } catch (_) {}
            return null;
          }
        }
      } catch (e) {
        // ignore file check errors
      }

      // Plugin may return an alternative path
      if (res is String && res.isNotEmpty) {
        try {
          final alt = File(res);
          if (await alt.exists() && await alt.length() > 0) return res;
        } catch (_) {}
      }

      return null;
    } catch (e) {
      Log.e('[AndroidTTS] Error synthesizeToFile (flutter_tts): $e');
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
      Log.e('[AndroidTTS] Error deteniendo síntesis: $e');
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
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getDownloadableLanguages',
      );
      if (result == null) return [];

      return result.map((lang) => Map<String, dynamic>.from(lang)).toList();
    } catch (e) {
      Log.e('[AndroidTTS] Error obteniendo idiomas descargables: $e');
      return [];
    }
  }

  /// Solicita la descarga de un idioma específico
  static Future<bool> requestLanguageDownload(String languageCode) async {
    if (!isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('requestDownload', {
        'languageCode': languageCode,
      });

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
      final result = await _channel.invokeMethod<String>('getDownloadStatus', {
        'languageCode': languageCode,
      });

      return result ?? 'unknown';
    } catch (e) {
      debugPrint('[AndroidTTS] Error obteniendo estado de descarga: $e');
      return 'error';
    }
  }

  /// Formatea la información de una voz para mostrar
  static String formatVoiceInfo(Map<String, dynamic> voice) {
    final name = voice['name'] as String? ?? 'Sin nombre';
    final locale = voice['locale'] as String? ?? '';
    final quality = voice['quality'] as String? ?? 'normal';
    // The platform plugin may return several shapes/keys for the network flag.
    // Accept: bool under 'requiresNetworkConnection', string/int under 'network_required', etc.
    bool isNetworkRequired = false;
    try {
      final nr =
          voice['requiresNetworkConnection'] ??
          voice['network_required'] ??
          voice['networkRequired'] ??
          voice['requires_network'];
      if (nr is bool) {
        isNetworkRequired = nr;
      } else if (nr is String) {
        final s = nr.trim().toLowerCase();
        isNetworkRequired = (s == '1' || s == 'true' || s == 'yes');
      } else if (nr is int) {
        isNetworkRequired = nr != 0;
      }
    } catch (_) {
      isNetworkRequired = false;
    }

    // If voice requires network, prefer showing 'Network' as the main label
    final qualityText = isNetworkRequired
        ? 'Network'
        : (quality == 'very_high'
              ? 'Neural'
              : quality == 'high'
              ? 'Local'
              : 'Normal');

    // Use centralized helper to obtain a language label like 'Español (España)'
    try {
      final languageLabel = VoiceDisplayUtils.getLanguageLabelFromVoice(voice);
      if (languageLabel.isNotEmpty) return '$languageLabel · $qualityText';
    } catch (_) {}

    // Fallback to older format if we can't produce a nice language/region label
    final fallbackLocale = locale.isNotEmpty ? locale : 'Sin idioma';
    return '$name - $fallbackLocale ($qualityText)';
  }

  /// Normaliza/limita el valor de speechRate al rango válido del plugin.
  static Future<double> _normalizeSpeechRate(double requested) async {
    try {
      // The plugin exposes a getter for the valid range. Use it if present.
      final range = await _flutterTts.getSpeechRateValidRange;
      final min = range.min;
      final normal = range.normal;
      final max = range.max;
      // Clamp
      if (requested.isNaN) return normal;
      if (requested < min) return min;
      if (requested > max) return max;
      return requested;
    } catch (e) {
      // Fallback conservative value
      return requested.clamp(0.3, 0.7);
    }
  }
}
