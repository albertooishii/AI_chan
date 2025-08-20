import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ai_chan/core/config.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:ai_chan/core/cache/cache_service.dart';
import 'package:ai_chan/shared/utils.dart';

// During tests we want to avoid noisy debug printing that looks like errors in CI logs.
bool _isFlutterTestRuntime() {
  try {
    // Flutter's test runner sets FLUTTER_TEST in the environment for test runs.
    return Platform.environment.containsKey('FLUTTER_TEST') ||
        Platform.environment['FLUTTER_TEST'] == 'true';
  } catch (_) {
    return false;
  }
}

void _maybeDebugPrint(String message) {
  if (!_isFlutterTestRuntime()) debugPrint(message);
}

class GoogleSpeechService {
  static String get _apiKey => Config.get('GOOGLE_CLOUD_API_KEY', '').trim();

  /// Convierte texto a voz usando Google Cloud Text-to-Speech con caché
  static Future<Uint8List?> textToSpeech({
    required String text,
    String languageCode = 'es-ES',
    String voiceName = 'es-ES-Neural2-A', // Voz femenina neural
    String audioEncoding = 'MP3',
    double speakingRate = 1.0,
    double pitch = 0.0,
  }) async {
    if (_apiKey.isEmpty) {
      _maybeDebugPrint(
        '[GoogleTTS] Error: GOOGLE_CLOUD_API_KEY no configurada',
      );
      return null;
    }

    if (text.trim().isEmpty) {
      _maybeDebugPrint('[GoogleTTS] Error: texto vacío');
      return null;
    }

    // Verificar caché primero
    try {
      final cachedFile = await CacheService.getCachedAudioFile(
        text: text,
        voice: voiceName,
        languageCode: languageCode,
        provider: 'google',
        speakingRate: speakingRate,
        pitch: pitch,
      );

      if (cachedFile != null) {
        _maybeDebugPrint('[GoogleTTS] Usando audio desde caché');
        return await cachedFile.readAsBytes();
      }
    } catch (e) {
      _maybeDebugPrint(
        '[GoogleTTS] Error leyendo caché, continuando con API: $e',
      );
    }

    final url = Uri.parse(
      'https://texttospeech.googleapis.com/v1/text:synthesize?key=$_apiKey',
    );

    final requestBody = {
      'input': {'text': text.trim()},
      'voice': {'languageCode': languageCode, 'name': voiceName},
      'audioConfig': {
        'audioEncoding': audioEncoding,
        'speakingRate': speakingRate,
        'pitch': pitch,
      },
    };

    try {
      _maybeDebugPrint(
        '[GoogleTTS] Sintetizando: "${text.length > 100 ? '${text.substring(0, 100)}...' : text}"',
      );

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final audioContent = data['audioContent'] as String?;

        if (audioContent != null) {
          final audioData = base64Decode(audioContent);
          _maybeDebugPrint(
            '[GoogleTTS] Audio generado exitosamente: ${audioData.length} bytes',
          );

          // Guardar en caché
          try {
            await CacheService.saveAudioToCache(
              audioData: audioData,
              text: text,
              voice: voiceName,
              languageCode: languageCode,
              provider: 'google',
              speakingRate: speakingRate,
              pitch: pitch,
            );
          } catch (e) {
            _maybeDebugPrint(
              '[GoogleTTS] Warning: Error guardando en caché: $e',
            );
          }

          return audioData;
        } else {
          _maybeDebugPrint(
            '[GoogleTTS] Error: respuesta sin contenido de audio',
          );
        }
      } else {
        _maybeDebugPrint(
          '[GoogleTTS] Error ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      _maybeDebugPrint('[GoogleTTS] Exception: $e');
    }

    return null;
  }

  /// Convierte texto a voz y guarda como archivo
  static Future<File?> textToSpeechFile({
    required String text,
    String? customFileName,
    String languageCode = 'es-ES',
    String voiceName = 'es-ES-Neural2-A',
    String audioEncoding = 'MP3',
    double speakingRate = 1.0,
    double pitch = 0.0,
  }) async {
    final audioData = await textToSpeech(
      text: text,
      languageCode: languageCode,
      voiceName: voiceName,
      audioEncoding: audioEncoding,
      speakingRate: speakingRate,
      pitch: pitch,
    );

    if (audioData == null) return null;

    try {
      final directory = await getTemporaryDirectory();
      final fileName =
          customFileName ??
          'google_tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final file = File('${directory.path}/$fileName');

      await file.writeAsBytes(audioData);
      _maybeDebugPrint('[GoogleTTS] Archivo guardado: ${file.path}');
      return file;
    } catch (e) {
      _maybeDebugPrint('[GoogleTTS] Error guardando archivo: $e');
      return null;
    }
  }

  /// Convierte voz a texto usando Google Cloud Speech-to-Text
  static Future<String?> speechToText({
    required Uint8List audioData,
    String languageCode = 'es-ES',
    String audioEncoding = 'WEBM_OPUS',
    int sampleRateHertz = 48000,
    bool enableAutomaticPunctuation = true,
  }) async {
    if (_apiKey.isEmpty) {
      _maybeDebugPrint(
        '[GoogleSTT] Error: GOOGLE_CLOUD_API_KEY no configurada',
      );
      return null;
    }

    if (audioData.isEmpty) {
      _maybeDebugPrint('[GoogleSTT] Error: datos de audio vacíos');
      return null;
    }

    final url = Uri.parse(
      'https://speech.googleapis.com/v1/speech:recognize?key=$_apiKey',
    );

    final audioContentBase64 = base64Encode(audioData);

    final requestBody = {
      'config': {
        'encoding': audioEncoding,
        'sampleRateHertz': sampleRateHertz,
        'languageCode': languageCode,
        'model': 'latest_long', // Modelo optimizado para audio largo
        'enableAutomaticPunctuation': enableAutomaticPunctuation,
        'useEnhanced': true, // Usar modelo mejorado
      },
      'audio': {'content': audioContentBase64},
    };

    try {
      _maybeDebugPrint(
        '[GoogleSTT] Transcribiendo audio: ${audioData.length} bytes',
      );

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          final alternatives = results[0]['alternatives'] as List?;
          if (alternatives != null && alternatives.isNotEmpty) {
            final transcript = alternatives[0]['transcript'] as String?;
            final confidence = alternatives[0]['confidence'] as double?;

            _maybeDebugPrint(
              '[GoogleSTT] Transcripción exitosa: "$transcript" (confianza: ${confidence?.toStringAsFixed(2)})',
            );
            return transcript?.trim();
          }
        } else {
          _maybeDebugPrint('[GoogleSTT] No se detectó habla en el audio');
        }
      } else {
        _maybeDebugPrint(
          '[GoogleSTT] Error ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      _maybeDebugPrint('[GoogleSTT] Exception: $e');
    }

    return null;
  }

  /// Transcribe un archivo de audio
  static Future<String?> speechToTextFromFile(
    File audioFile, {
    String languageCode = 'es-ES',
    String audioEncoding = 'MP3',
    int sampleRateHertz = 24000,
  }) async {
    try {
      final audioData = await audioFile.readAsBytes();
      return await speechToText(
        audioData: audioData,
        languageCode: languageCode,
        audioEncoding: audioEncoding,
        sampleRateHertz: sampleRateHertz,
      );
    } catch (e) {
      _maybeDebugPrint('[GoogleSTT] Error leyendo archivo: $e');
      return null;
    }
  }

  /// Fetch the official list of Google TTS voices from the API and cache it locally.
  /// Returns a list of maps with keys: name, languageCodes, ssmlGender, naturalSampleRateHertz
  static Future<List<Map<String, dynamic>>> fetchGoogleVoices({
    bool forceRefresh = false,
  }) async {
    if (!isConfigured) {
      _maybeDebugPrint('[GoogleTTS] fetchGoogleVoices: not configured');
      return [];
    }

    try {
      // Intentar obtener desde caché primero
      if (!forceRefresh) {
        final cachedVoices = await CacheService.getCachedVoices(
          provider: 'google',
        );
        if (cachedVoices != null) {
          _maybeDebugPrint(
            '[GoogleTTS] Usando ${cachedVoices.length} voces desde caché',
          );
          return cachedVoices;
        }
      }

      final url = Uri.parse(
        'https://texttospeech.googleapis.com/v1/voices?key=$_apiKey',
      );
      final resp = await http.get(url);

      if (resp.statusCode != 200) {
        _maybeDebugPrint(
          '[GoogleTTS] fetchGoogleVoices error ${resp.statusCode}: ${resp.body}',
        );

        // Si hay error, intentar usar caché como fallback
        final fallbackVoices = await CacheService.getCachedVoices(
          provider: 'google',
          forceRefresh: false,
        );
        if (fallbackVoices != null) {
          _maybeDebugPrint(
            '[GoogleTTS] Usando caché como fallback tras error de API',
          );
          return fallbackVoices;
        }
        return [];
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final voices = (data['voices'] as List<dynamic>?) ?? [];

      final processedVoices = voices
          .map(
            (v) => {
              'name': v['name'],
              'languageCodes': (v['languageCodes'] as List<dynamic>)
                  .cast<String>(),
              'ssmlGender': v['ssmlGender'],
              'naturalSampleRateHertz': v['naturalSampleRateHertz'],
            },
          )
          .toList();

      // Guardar en caché
      try {
        await CacheService.saveVoicesToCache(
          voices: processedVoices,
          provider: 'google',
        );
      } catch (e) {
        debugPrint('[GoogleTTS] Warning: Error guardando voces en caché: $e');
      }

      _maybeDebugPrint(
        '[GoogleTTS] Obtenidas ${processedVoices.length} voces desde API',
      );
      return processedVoices;
    } catch (e) {
      _maybeDebugPrint('[GoogleTTS] Exception fetching voices: $e');

      // Intentar caché como último recurso
      final fallbackVoices = await CacheService.getCachedVoices(
        provider: 'google',
        forceRefresh: false,
      );
      if (fallbackVoices != null) {
        _maybeDebugPrint(
          '[GoogleTTS] Usando caché como último recurso tras excepción',
        );
        return fallbackVoices;
      }
      return [];
    }
  }

  /// Return female voices that match the provided language codes (AI country and user country).
  /// Each languageCode can be a 2-letter code ('ja') or a region code ('ja-JP').
  /// If both lists are empty, defaults to Spanish (Spain) voices.
  static Future<List<Map<String, dynamic>>> voicesForUserAndAi(
    List<String> userLanguageCodes,
    List<String> aiLanguageCodes, {
    bool forceRefresh = false,
  }) async {
    final all = await fetchGoogleVoices(forceRefresh: forceRefresh);

    // If both lists are empty, default to Spanish (Spain)
    List<String> allLanguageCodes = [...userLanguageCodes, ...aiLanguageCodes];
    if (allLanguageCodes.isEmpty) {
      allLanguageCodes = ['es-ES'];
    }

    // Normalize all language codes to lowercase for exact matching
    final Set<String> targetCodes = {};
    for (final code in allLanguageCodes) {
      if (code.trim().isNotEmpty) {
        final norm = code.trim().toLowerCase();
        targetCodes.add(norm);
        // NO agregamos prefijos para evitar matches no deseados como es-US cuando queremos es-ES
      }
    }

    List<Map<String, dynamic>> filtered = [];

    for (final v in all) {
      final languageCodes = (v['languageCodes'] as List<dynamic>)
          .cast<String>();
      final ssmlGender = (v['ssmlGender'] as String? ?? '').toUpperCase();

      // Only include female voices
      if (ssmlGender != 'FEMALE') continue;

      // Check if any voice language code matches our target codes EXACTLY
      final matches = languageCodes.any((lc) {
        final low = lc.toLowerCase();
        return targetCodes.contains(low);
      });

      if (matches) filtered.add(v);
    }

    // Remove duplicates by name preserving order
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final v in filtered) {
      final name = v['name'] as String? ?? '';
      if (!seen.contains(name)) {
        seen.add(name);
        unique.add(v);
      }
    }

    return unique;
  }

  /// Legacy method - kept for backward compatibility
  ///
  /// Deprecated: use `voicesForUserAndAi(List<String> userCodes, List<String> aiCodes, {bool forceRefresh = false})`
  /// instead. This method will be removed in a future release.
  @Deprecated(
    'use voicesForUserAndAi(List<String> userCodes, List<String> aiCodes, {bool forceRefresh = false}) instead',
  )
  static Future<List<Map<String, dynamic>>> voicesForAiAndSpanish(
    String? aiLanguageCode, {
    bool forceRefresh = false,
  }) async {
    return voicesForUserAndAi(
      ['es-ES'],
      [aiLanguageCode ?? 'es-ES'],
      forceRefresh: forceRefresh,
    );
  }

  /// Obtiene configuración de voz desde variables de entorno
  static Map<String, dynamic> getVoiceConfig() {
    // Voice name may be configurable, but language, speaking rate and pitch are
    // intentionally hardcoded per project policy (do not use env to override).
    final voiceName = Config.get('GOOGLE_VOICE_NAME', 'es-ES-Neural2-A');
    final languageCode = resolveDefaultLanguageCode();
    final speakingRate = 1.0;
    final pitch = 0.0;

    return {
      'voiceName': voiceName,
      'languageCode': languageCode,
      'speakingRate': speakingRate,
      'pitch': pitch,
    };
  }

  /// Resolve a sensible default language code for Google TTS.
  /// Priority: provided country ISO2 -> LocaleUtils mapping -> system locale -> fallback 'es-ES'.
  static String resolveDefaultLanguageCode([String? countryIso2]) {
    try {
      if (countryIso2 != null && countryIso2.trim().isNotEmpty) {
        final codes = LocaleUtils.officialLanguageCodesForCountry(
          countryIso2.trim().toUpperCase(),
        );
        if (codes.isNotEmpty) return codes.first;
      }
    } catch (_) {}
    try {
      // Platform.localeName often looks like 'es_ES' or 'en_US'. Convert to 'es-ES'.
      final locale = Platform.localeName.replaceAll('_', '-');
      final parts = locale.split('-');
      if (parts.isNotEmpty) {
        final lang = parts[0].toLowerCase();
        final region = parts.length > 1 ? parts[1].toUpperCase() : '';
        return region.isNotEmpty ? '\${lang}-\$region' : lang;
      }
    } catch (_) {}
    return 'es-ES';
  }

  /// Verifica si el servicio está configurado correctamente
  static bool get isConfigured => _apiKey.isNotEmpty;

  /// Limpia el caché de voces de Google, forzando una nueva descarga en la próxima consulta
  static Future<void> clearVoicesCache() async {
    try {
      await CacheService.clearVoicesCache(provider: 'google');
      debugPrint('[GoogleTTS] Caché de voces Google limpiado');
    } catch (e) {
      debugPrint('[GoogleTTS] Error limpiando caché de voces: $e');
    }
  }
}
