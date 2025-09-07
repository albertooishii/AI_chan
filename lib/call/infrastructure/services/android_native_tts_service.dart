import 'dart:io';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ai_chan/shared/utils/voice_display_utils.dart';
import 'package:ai_chan/core/interfaces/i_native_tts_service.dart';

// NOTE: We are deprecating the native MethodChannel-based Android TTS shim.
// Internally the app now prefers the Dart plugin `flutter_tts`. This file
// preserves the public API used by the app but delegates to FlutterTts when
// possible. Methods that required native-only behaviors (synthesizeToFile)
// will return null and callers should use cloud services or the
// GoogleSpeechService.textToSpeechFile for persisted audio.

class AndroidNativeTtsService implements INativeTtsService {
  static const MethodChannel _channel = MethodChannel('ai_chan/native_tts');

  static bool get isAndroid => Platform.isAndroid;

  static final FlutterTts _flutterTts = FlutterTts();

  @override
  Future<String?> synthesizeToFile({
    required final String text,
    final Map<String, dynamic>? options,
  }) async {
    final outputPath = options?['outputPath'] as String? ?? '';
    final voiceName = options?['voiceName'] as String?;
    final languageCode = options?['languageCode'] as String? ?? 'es-ES';
    final pitch = options?['pitch'] as double? ?? 1.0;
    final speechRate = options?['speechRate'] as double? ?? 0.5;

    return synthesizeToFileLegacy(
      text: text,
      outputPath: outputPath,
      voiceName: voiceName,
      languageCode: languageCode,
      pitch: pitch,
      speechRate: speechRate,
    );
  }

  /// Verifica si el TTS nativo de Android está disponible (versión estática)
  static Future<bool> checkNativeTtsAvailable() async {
    if (!isAndroid) return false;
    try {
      // The Dart plugin is always available when running on Android.
      return true;
    } on Exception catch (e) {
      Log.e('[AndroidTTS] Error verificando disponibilidad (flutter_tts): $e');
      return false;
    }
  }

  /// Obtiene la lista de voces disponibles en el sistema Android (versión estática)
  static Future<List<Map<String, dynamic>>> getVoices() async {
    if (!isAndroid) return [];
    try {
      final voices = await _flutterTts.getVoices;
      if (voices == null) return [];
      return (voices as List<dynamic>)
          .map((final v) => Map<String, dynamic>.from(v as Map))
          .toList();
    } on Exception catch (e) {
      Log.e('[AndroidTTS] Error obteniendo voces (flutter_tts): $e');
      return [];
    }
  }

  /// Filtra la lista completa de voces según códigos de usuario y de AI (versión estática).
  /// Comportamiento:
  /// - Normaliza '_' a '-' y pasa a minúsculas.
  /// - Si se solicita al menos un código con región, requiere coincidencia exacta de región.
  /// - En caso contrario, permite coincidencia por idioma.
  static Future<List<Map<String, dynamic>>> filterVoicesByCodes(
    final List<Map<String, dynamic>> voices,
    final List<String> userCodes,
    final List<String> aiCodes,
  ) async {
    final all = voices;
    final allLanguageCodes = <String>[];
    for (final c in [...userCodes, ...aiCodes]) {
      if (c.trim().isEmpty) continue;
      allLanguageCodes.add(c.replaceAll('_', '-').toLowerCase());
    }
    if (allLanguageCodes.isEmpty) return all;

    final Set<String> targetCodes = allLanguageCodes.toSet();
    final hasExactRegion = targetCodes.any((final t) => t.contains('-'));

    return all.where((final voice) {
      final Set<String> voiceLangCodes = {};
      try {
        final languageCodesField = voice['languageCodes'];
        if (languageCodesField is List && languageCodesField.isNotEmpty) {
          for (final lc in languageCodesField.cast<String>()) {
            voiceLangCodes.add(lc.replaceAll('_', '-').toLowerCase());
          }
        }
      } on Exception catch (_) {}

      var locale = (voice['locale'] as String?) ?? '';
      locale = locale.replaceAll('_', '-').toLowerCase();

      if (hasExactRegion) {
        final exactTargets = targetCodes
            .where((final t) => t.contains('-'))
            .toSet();
        if (voiceLangCodes.isNotEmpty) {
          if (voiceLangCodes.any((final vlc) => exactTargets.contains(vlc))) {
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
            (final vlc) => vlc == tLang || vlc.startsWith('$tLang-'),
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

  /// Formatea la información de una voz para mostrar (versión estática)
  static String formatVoiceInfoStatic(final Map<String, dynamic> voice) {
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
    } on Exception catch (_) {
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
    } on Exception catch (_) {}

    // Fallback to older format if we can't produce a nice language/region label
    final fallbackLocale = locale.isNotEmpty ? locale : 'Sin idioma';
    return '$name - $fallbackLocale ($qualityText)';
  }

  /// Método de debug para volcar JSON de voces para un idioma específico (versión estática)
  static Future<void> dumpVoicesJsonForLanguage(
    final String languageCode, {
    final bool exactOnly = false,
  }) async {
    if (!isAndroid) return;
    try {
      final allVoices = await getVoices();
      final filtered = await filterVoicesByCodes(allVoices, [languageCode], []);
      Log.d(
        '[AndroidTTS] DEBUG dumpVoicesJsonForLanguage($languageCode, exactOnly=$exactOnly):',
      );
      Log.d(
        '[AndroidTTS] Total voices: ${allVoices.length}, Filtered: ${filtered.length}',
      );
      for (final voice in filtered.take(5)) {
        Log.d('[AndroidTTS] Voice: ${voice['name']} - ${voice['locale']}');
      }
    } on Exception catch (e) {
      Log.e('[AndroidTTS] Error in dumpVoicesJsonForLanguage: $e');
    }
  }

  /// Alias estático para isNativeTtsAvailable (para compatibilidad con llamadas estáticas)
  static Future<bool> isNativeTtsAvailableStatic() async {
    return checkNativeTtsAvailable();
  }

  /// Alias estático para getAvailableVoices (para compatibilidad con llamadas estáticas)
  static Future<List<Map<String, dynamic>>> getAvailableVoicesStatic() async {
    return getVoices();
  }

  /// Sintetiza texto a archivo de audio (versión estática)
  static Future<String?> synthesizeToFileStatic({
    required final String text,
    required final String outputPath,
    final String? voiceName,
    final String languageCode = 'es-ES',
    final double pitch = 1.0,
    final double speechRate = 0.5,
  }) async {
    return synthesizeToFileLegacy(
      text: text,
      outputPath: outputPath,
      voiceName: voiceName,
      languageCode: languageCode,
      pitch: pitch,
      speechRate: speechRate,
    );
  }

  /// Verifica si el TTS nativo de Android está disponible
  @override
  Future<bool> isNativeTtsAvailable() async {
    return checkNativeTtsAvailable();
  }

  /// Obtiene la lista de voces disponibles en el sistema Android
  @override
  Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    return getVoices();
  }

  /// Obtiene voces filtradas por idioma
  @override
  Future<List<Map<String, dynamic>>> getVoicesForLanguage(
    final String languageCode,
  ) async {
    final allVoices = await getAvailableVoices();

    // Normalizar requested code: reemplazar '_' por '-' y pasar a minúsculas
    final requested = languageCode.replaceAll('_', '-').toLowerCase();

    // Primero intentar coincidencia exacta (lang-region) si se proporcionó región
    final requestedParts = requested.split('-');
    if (requestedParts.length >= 2) {
      final exact = allVoices.where((final voice) {
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
    return allVoices.where((final voice) {
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
  @override
  Future<List<Map<String, dynamic>>> filterVoicesByTargetCodes(
    final List<Map<String, dynamic>> voices,
    final List<String> userCodes,
    final List<String> aiCodes,
  ) async {
    final all = voices;
    final allLanguageCodes = <String>[];
    for (final c in [...userCodes, ...aiCodes]) {
      if (c.trim().isEmpty) continue;
      allLanguageCodes.add(c.replaceAll('_', '-').toLowerCase());
    }
    if (allLanguageCodes.isEmpty) return all;

    final Set<String> targetCodes = allLanguageCodes.toSet();
    final hasExactRegion = targetCodes.any((final t) => t.contains('-'));

    return all.where((final voice) {
      final Set<String> voiceLangCodes = {};
      try {
        final languageCodesField = voice['languageCodes'];
        if (languageCodesField is List && languageCodesField.isNotEmpty) {
          for (final lc in languageCodesField.cast<String>()) {
            voiceLangCodes.add(lc.replaceAll('_', '-').toLowerCase());
          }
        }
      } on Exception catch (_) {}

      var locale = (voice['locale'] as String?) ?? '';
      locale = locale.replaceAll('_', '-').toLowerCase();

      if (hasExactRegion) {
        final exactTargets = targetCodes
            .where((final t) => t.contains('-'))
            .toSet();
        if (voiceLangCodes.isNotEmpty) {
          if (voiceLangCodes.any((final vlc) => exactTargets.contains(vlc))) {
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
            (final vlc) => vlc == tLang || vlc.startsWith('$tLang-'),
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

  /// Detiene la síntesis actual
  @override
  Future<bool> stop() async {
    if (!isAndroid) return false;

    try {
      final result = await _channel.invokeMethod<bool>('stop');
      return result ?? false;
    } on Exception catch (e) {
      Log.e('[AndroidTTS] Error deteniendo síntesis: $e');
      return false;
    }
  }

  /// Obtiene información sobre voces disponibles para descargar
  @override
  Future<List<Map<String, dynamic>>> getDownloadableLanguages() async {
    if (!isAndroid) return [];

    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getDownloadableLanguages',
      );
      if (result == null) return [];

      return result
          .map((final lang) => Map<String, dynamic>.from(lang))
          .toList();
    } on Exception catch (e) {
      Log.e('[AndroidTTS] Error obteniendo idiomas descargables: $e');
      return [];
    }
  }

  /// Verifica el estado de descarga de un idioma
  @override
  Future<String> getLanguageDownloadStatus(final String languageCode) async {
    if (!isAndroid) return 'not_supported';

    try {
      final result = await _channel.invokeMethod<String>('getDownloadStatus', {
        'languageCode': languageCode,
      });

      return result ?? 'unknown';
    } on Exception catch (e) {
      debugPrint('[AndroidTTS] Error obteniendo estado de descarga: $e');
      return 'error';
    }
  }

  /// Formatea la información de una voz para mostrar
  @override
  String formatVoiceInfo(final Map<String, dynamic> voice) {
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
    } on Exception catch (_) {
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
    } on Exception catch (_) {}

    // Fallback to older format if we can't produce a nice language/region label
    final fallbackLocale = locale.isNotEmpty ? locale : 'Sin idioma';
    return '$name - $fallbackLocale ($qualityText)';
  }

  /// Sintetiza texto a archivo de audio (método legacy mantenido por compatibilidad)
  static Future<String?> synthesizeToFileLegacy({
    required final String text,
    required final String outputPath,
    final String? voiceName,
    final String languageCode = 'es-ES',
    final double pitch = 1.0,
    final double speechRate = 0.5,
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
      } on Exception {
        await _flutterTts.setSpeechRate(speechRate);
      }

      // Ask plugin to await completion so we can verify file
      try {
        await _flutterTts.awaitSynthCompletion(true);
      } on Exception catch (_) {}

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
        if (f.existsSync()) {
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
            } on Exception catch (_) {}
            return null;
          }
        }
      } on Exception catch (_) {
        // TTS synthesis failed, continue to alternatives
      }

      // Plugin may return an alternative path
      if (res is String && res.isNotEmpty) {
        try {
          final alt = File(res);
          if (alt.existsSync() && await alt.length() > 0) return res;
        } on Exception catch (_) {}
      }

      return null;
    } on Exception catch (e) {
      Log.e('[AndroidTTS] Error synthesizeToFile (flutter_tts): $e');
      return null;
    }
  }

  /// Normaliza/limita el valor de speechRate al rango válido del plugin.
  static Future<double> _normalizeSpeechRate(final double requested) async {
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
    } on Exception {
      // Fallback conservative value
      return requested.clamp(0.3, 0.7);
    }
  }
}
