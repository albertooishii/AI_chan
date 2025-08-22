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
    return Platform.environment.containsKey('FLUTTER_TEST') || Platform.environment['FLUTTER_TEST'] == 'true';
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
    int sampleRateHertz = 24000,
    bool noCache = false,
    bool useCache = false,
    double speakingRate = 1.0,
    double pitch = 0.0,
  }) async {
    _maybeDebugPrint(
      '[GoogleTTS] textToSpeech called - text: "${text.length} chars", voice: $voiceName, lang: $languageCode',
    );

    if (_apiKey.isEmpty) {
      _maybeDebugPrint('[GoogleTTS] Error: GOOGLE_CLOUD_API_KEY no configurada');
      return null;
    }

    if (text.trim().isEmpty) {
      _maybeDebugPrint('[GoogleTTS] Error: texto vacío');
      return null;
    }

    // Normalize voiceName: if caller passed an OpenAI voice name or empty,
    // replace with configured Google default so cache keys and API calls
    // are consistent.
    try {
      const openAIVoices = ['sage', 'alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];
      if (voiceName.trim().isEmpty || openAIVoices.contains(voiceName)) {
        final googleDefault = Config.getGoogleVoice();
        if (googleDefault.isNotEmpty) {
          _maybeDebugPrint('[GoogleTTS] Normalizing voiceName "$voiceName" -> Google default: $googleDefault');
          voiceName = googleDefault;
        }
      }
    } catch (_) {}

    // Determine likely extension from requested encoding (used for cache keys)
    String ext = 'mp3';
    final fmtCheck = audioEncoding.toLowerCase();
    if (fmtCheck.contains('linear16') || fmtCheck.contains('wav')) ext = 'wav';
    if (fmtCheck.contains('ogg') || fmtCheck.contains('opus')) ext = 'ogg';

    // Verificar caché primero solo si useCache=true
    if (useCache) {
      try {
        final cachedFile = await CacheService.getCachedAudioFile(
          text: text,
          voice: voiceName,
          languageCode: languageCode,
          provider: 'google',
          speakingRate: speakingRate,
          pitch: pitch,
          extension: ext,
        );

        if (cachedFile != null) {
          _maybeDebugPrint('[GoogleTTS] Usando audio desde caché');
          return await cachedFile.readAsBytes();
        }
      } catch (e) {
        _maybeDebugPrint('[GoogleTTS] Error leyendo caché, continuando con API: $e');
      }
    }

    final url = Uri.parse('https://texttospeech.googleapis.com/v1/text:synthesize?key=$_apiKey');

    final requestBody = {
      'input': {'text': text.trim()},
      'voice': {'languageCode': languageCode, 'name': voiceName},
      'audioConfig': {'audioEncoding': audioEncoding, 'speakingRate': speakingRate, 'pitch': pitch},
    };

    try {
      _maybeDebugPrint('[GoogleTTS] Sintetizando: "${text.length > 100 ? '${text.substring(0, 100)}...' : text}"');

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
          _maybeDebugPrint('[GoogleTTS] Audio generado exitosamente: ${audioData.length} bytes');

          // Guardar en caché solo si useCache=true y noCache==false
          if (useCache && !noCache) {
            try {
              await CacheService.saveAudioToCache(
                audioData: audioData,
                text: text,
                voice: voiceName,
                languageCode: languageCode,
                provider: 'google',
                speakingRate: speakingRate,
                pitch: pitch,
                extension: ext,
              );
            } catch (e) {
              _maybeDebugPrint('[GoogleTTS] Warning: Error guardando en caché: $e');
            }
          }

          return audioData;
        } else {
          _maybeDebugPrint('[GoogleTTS] Error: respuesta sin contenido de audio');
        }
      } else {
        _maybeDebugPrint('[GoogleTTS] Error ${response.statusCode}: ${response.body}');
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
    int sampleRateHertz = 24000,
    bool noCache = false,
    bool useCache = false,
    double speakingRate = 1.0,
    double pitch = 0.0,
  }) async {
    // Normalize voiceName early so cache lookup uses the Google voice name
    // (avoids regenerating audio that was cached under the Google default).
    try {
      const openAIVoices = ['sage', 'alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];
      if (voiceName.trim().isEmpty || openAIVoices.contains(voiceName)) {
        final googleDefault = Config.getGoogleVoice();
        if (googleDefault.isNotEmpty) {
          _maybeDebugPrint('[GoogleTTS] Normalizing voiceName in file flow "$voiceName" -> $googleDefault');
          voiceName = googleDefault;
        }
      }
    } catch (_) {}

    // First, check if there's a cached file for this exact request and return it
    // directly to avoid creating a temporary copy and to ensure callers use
    // the cached path.
    if (useCache) {
      try {
        final cachedFile = await CacheService.getCachedAudioFile(
          text: text,
          voice: voiceName,
          languageCode: languageCode,
          provider: 'google',
          speakingRate: speakingRate,
          pitch: pitch,
          extension: audioEncoding.toLowerCase().contains('wav') ? 'wav' : 'mp3',
        );
        if (cachedFile != null) {
          _maybeDebugPrint('[GoogleTTS] Returning cached file path directly: ${cachedFile.path}');
          return cachedFile;
        }
      } catch (e) {
        _maybeDebugPrint('[GoogleTTS] Error checking cache before file creation: $e');
      }
    }

    final audioData = await textToSpeech(
      text: text,
      languageCode: languageCode,
      voiceName: voiceName,
      audioEncoding: audioEncoding,
      sampleRateHertz: sampleRateHertz,
      noCache: noCache,
      useCache: useCache,
      speakingRate: speakingRate,
      pitch: pitch,
    );

    if (audioData == null) return null;

    try {
      final directory = await getTemporaryDirectory();
      // Decide extension based on requested encoding/format
      String ext = 'mp3';
      final fmt = audioEncoding.toLowerCase();
      if (fmt.contains('linear16') ||
          fmt.contains('wav') ||
          (customFileName?.toLowerCase().endsWith('.wav') ?? false)) {
        ext = 'wav';
      } else if (fmt.contains('ogg') || fmt.contains('opus')) {
        ext = 'ogg';
      } else if (fmt.contains('mp3')) {
        ext = 'mp3';
      }
      final fileName = customFileName ?? 'google_tts_${DateTime.now().millisecondsSinceEpoch}.$ext';
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
      _maybeDebugPrint('[GoogleSTT] Error: GOOGLE_CLOUD_API_KEY no configurada');
      return null;
    }

    if (audioData.isEmpty) {
      _maybeDebugPrint('[GoogleSTT] Error: datos de audio vacíos');
      return null;
    }

    final url = Uri.parse('https://speech.googleapis.com/v1/speech:recognize?key=$_apiKey');

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
      _maybeDebugPrint('[GoogleSTT] Transcribiendo audio: ${audioData.length} bytes');

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
        _maybeDebugPrint('[GoogleSTT] Error ${response.statusCode}: ${response.body}');
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

      // Detect WAV header (RIFF) and extract PCM chunk and sample rate if present.
      try {
        if (audioData.length > 12) {
          final header = String.fromCharCodes(audioData.sublist(0, 4));
          if (header == 'RIFF') {
            // read sampleRate from fmt chunk (offset 24..27 little endian)
            int sr = sampleRateHertz;
            try {
              sr = audioData[24] | (audioData[25] << 8) | (audioData[26] << 16) | (audioData[27] << 24);
            } catch (_) {}
            // Extract pcm data chunk (look for 'data')
            int dataStart = -1;
            for (int i = 0; i < audioData.length - 4; i++) {
              if (audioData[i] == 0x64 &&
                  audioData[i + 1] == 0x61 &&
                  audioData[i + 2] == 0x74 &&
                  audioData[i + 3] == 0x61) {
                dataStart = i + 8; // skip 'data' + size (4 bytes)
                break;
              }
            }
            if (dataStart > 0) {
              final pcm = audioData.sublist(dataStart);
              return await speechToText(
                audioData: pcm,
                languageCode: languageCode,
                audioEncoding: 'LINEAR16',
                sampleRateHertz: sr,
              );
            }
          }
        }
      } catch (e) {
        _maybeDebugPrint('[GoogleSTT] Warning parsing WAV header: $e');
      }

      // Fallback: assume raw PCM16 captured by recorder (sampleRate 16000)
      // Many recorder streams provide raw 16-bit PCM without WAV header.
      return await speechToText(
        audioData: audioData,
        languageCode: languageCode,
        audioEncoding: 'LINEAR16',
        sampleRateHertz: 16000,
      );
    } catch (e) {
      _maybeDebugPrint('[GoogleSTT] Error leyendo archivo: $e');
      return null;
    }
  }

  /// Fetch the official list of Google TTS voices from the API and cache it locally.
  /// Returns a list of maps with keys: name, languageCodes, ssmlGender, naturalSampleRateHertz
  static Future<List<Map<String, dynamic>>> fetchGoogleVoices({bool forceRefresh = false}) async {
    _maybeDebugPrint('[GoogleTTS] fetchGoogleVoices INICIADO - forceRefresh=$forceRefresh');

    if (!isConfigured) {
      _maybeDebugPrint('[GoogleTTS] fetchGoogleVoices: not configured');
      return [];
    }

    try {
      // Intentar obtener desde caché primero
      if (!forceRefresh) {
        _maybeDebugPrint('[GoogleTTS] Intentando obtener desde caché...');
        final cachedVoices = await CacheService.getCachedVoices(provider: 'google');
        if (cachedVoices != null) {
          _maybeDebugPrint('[GoogleTTS] Usando ${cachedVoices.length} voces desde caché');
          return cachedVoices;
        }
        _maybeDebugPrint('[GoogleTTS] No hay caché, procediendo a API...');
      } else {
        _maybeDebugPrint('[GoogleTTS] ForceRefresh=true - saltando caché, yendo directo a API');
      }

      _maybeDebugPrint('[GoogleTTS] Haciendo llamada HTTP a Google TTS API...');
      final url = Uri.parse('https://texttospeech.googleapis.com/v1/voices?key=$_apiKey');
      final resp = await http.get(url).timeout(Duration(seconds: 30));
      _maybeDebugPrint('[GoogleTTS] Respuesta HTTP recibida: ${resp.statusCode}');

      if (resp.statusCode != 200) {
        _maybeDebugPrint('[GoogleTTS] fetchGoogleVoices error ${resp.statusCode}: ${resp.body}');

        // Si hay error, intentar usar caché como fallback
        final fallbackVoices = await CacheService.getCachedVoices(provider: 'google', forceRefresh: false);
        if (fallbackVoices != null) {
          _maybeDebugPrint('[GoogleTTS] Usando caché como fallback tras error de API');
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
              'languageCodes': (v['languageCodes'] as List<dynamic>).cast<String>(),
              'ssmlGender': v['ssmlGender'],
              'naturalSampleRateHertz': v['naturalSampleRateHertz'],
            },
          )
          .toList();

      // Guardar en caché
      try {
        await CacheService.saveVoicesToCache(voices: processedVoices, provider: 'google');
      } catch (e) {
        _maybeDebugPrint('[GoogleTTS] Warning: Error guardando voces en caché: $e');
      }

      _maybeDebugPrint('[GoogleTTS] Obtenidas ${processedVoices.length} voces desde API');
      return processedVoices;
    } catch (e) {
      _maybeDebugPrint('[GoogleTTS] Exception fetching voices: $e');

      // Intentar caché como último recurso
      final fallbackVoices = await CacheService.getCachedVoices(provider: 'google', forceRefresh: false);
      if (fallbackVoices != null) {
        _maybeDebugPrint('[GoogleTTS] Usando caché como último recurso tras excepción');
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
      final languageCodes = (v['languageCodes'] as List<dynamic>).cast<String>();
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

  /// Cachea los resultados y permite forzar refresh.
  static Future<List<Map<String, dynamic>>> getNeuralWaveNetVoices(
    List<String> userLanguageCodes,
    List<String> aiLanguageCodes, {
    bool forceRefresh = false,
  }) async {
    _maybeDebugPrint('[GoogleTTS] getNeuralWaveNetVoices INICIADO - forceRefresh=$forceRefresh');
    try {
      // Generar clave de caché específica
      final allLanguageCodes = [...userLanguageCodes, ...aiLanguageCodes];
      final languageKey = allLanguageCodes.isEmpty ? 'es-ES' : allLanguageCodes.join('_');
      final cacheKey = 'neural_wavenet_$languageKey';

      _maybeDebugPrint('[GoogleTTS] Cache key: $cacheKey, forceRefresh: $forceRefresh');

      // Si no es refresh forzado, intentar obtener desde caché
      if (!forceRefresh) {
        final cachedVoices = await CacheService.getCachedVoices(provider: cacheKey);
        if (cachedVoices != null) {
          _maybeDebugPrint('[GoogleTTS] Usando ${cachedVoices.length} voces Neural/WaveNet desde caché');
          return cachedVoices;
        }
      } else {
        _maybeDebugPrint('[GoogleTTS] FORCE REFRESH ACTIVADO - saltando caché');
      }

      // Obtener todas las voces directamente de la API
      _maybeDebugPrint('[GoogleTTS] Obteniendo voces Neural desde API con forceRefresh...');
      final allVoices = await fetchGoogleVoices(forceRefresh: true);

      // Normalizar códigos de idioma para comparación exacta
      final Set<String> targetCodes = {};
      for (final code in allLanguageCodes) {
        if (code.trim().isNotEmpty) {
          targetCodes.add(code.trim().toLowerCase());
        }
      }
      if (targetCodes.isEmpty) {
        targetCodes.add('es-es'); // Fallback a español
      }

      _maybeDebugPrint('[GoogleTTS] Target language codes: $targetCodes');

      // Debug: listar TODAS las voces antes de filtrar
      _maybeDebugPrint('[GoogleTTS] TOTAL de voces desde API: ${allVoices.length}');

      // Debug: buscar WaveNet específicamente Y TODAS las voces que contengan "Wavenet"
      final waveNetVoices = allVoices.where((v) {
        final name = (v['name'] as String? ?? '').toLowerCase();
        return name.contains('wavenet');
      }).toList();
      _maybeDebugPrint('[GoogleTTS] Voces WaveNet encontradas en API (case insensitive): ${waveNetVoices.length}');

      // Debug: buscar específicamente voces españolas WaveNet
      final spanishWaveNet = allVoices.where((v) {
        final name = (v['name'] as String? ?? '').toLowerCase();
        final langs = (v['languageCodes'] as List<dynamic>? ?? []).cast<String>();
        final hasWaveNet = name.contains('wavenet');
        final isSpanish = langs.any((lang) => lang.toLowerCase().startsWith('es'));
        return hasWaveNet && isSpanish;
      }).toList();
      _maybeDebugPrint('[GoogleTTS] Voces WaveNet ESPAÑOLAS encontradas: ${spanishWaveNet.length}');

      // Filtrar voces según criterios:
      // 1. Solo femeninas
      // 2. Solo Neural o WaveNet
      // 3. Solo idiomas especificados
      final filteredVoices = allVoices.where((voice) {
        final name = voice['name'] as String? ?? '';
        final gender = (voice['ssmlGender'] as String? ?? '').toUpperCase();
        final languageCodes = (voice['languageCodes'] as List<dynamic>).cast<String>();

        // Filtro 1: Solo femeninas
        if (gender != 'FEMALE') {
          return false;
        }

        // Filtro 2: Solo Neural o WaveNet (case insensitive)
        final isNeural = name.toLowerCase().contains('neural');
        final isWaveNet = name.toLowerCase().contains('wavenet'); // case insensitive
        if (!isNeural && !isWaveNet) {
          return false;
        }

        // Filtro 3: Solo idiomas especificados
        final matches = languageCodes.any((lc) {
          final normalized = lc.toLowerCase();
          return targetCodes.contains(normalized);
        });

        return matches;
      }).toList();

      _maybeDebugPrint('[GoogleTTS] Voces después del filtro: ${filteredVoices.length}');

      // Eliminar duplicados por nombre
      final seen = <String>{};
      final unique = <Map<String, dynamic>>[];
      for (final voice in filteredVoices) {
        final name = voice['name'] as String? ?? '';
        if (!seen.contains(name)) {
          seen.add(name);
          unique.add(voice);
        }
      }

      _maybeDebugPrint('[GoogleTTS] Filtradas ${unique.length} voces Neural femeninas');

      // Debug: listar voces encontradas
      for (final voice in unique) {
        final name = voice['name'] as String? ?? '';
        _maybeDebugPrint('[GoogleTTS] $name');
      }

      // Guardar en caché
      try {
        await CacheService.saveVoicesToCache(voices: unique, provider: cacheKey);
        _maybeDebugPrint('[GoogleTTS] Guardadas ${unique.length} voces en caché ($cacheKey)');
      } catch (e) {
        debugPrint('[GoogleTTS] Warning: Error guardando en caché: $e');
      }

      debugPrint('🚨🚨🚨 [GoogleTTS] RETORNANDO ${unique.length} voces Neural/WaveNet 🚨🚨🚨');
      return unique;
    } catch (e) {
      debugPrint('🚨🚨🚨 [GoogleTTS] ERROR: $e 🚨🚨🚨');
      debugPrint('[GoogleTTS] Error obteniendo voces Neural/WaveNet: $e');
      return [];
    }
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
    return voicesForUserAndAi(['es-ES'], [aiLanguageCode ?? 'es-ES'], forceRefresh: forceRefresh);
  }

  /// Obtiene configuración de voz desde variables de entorno
  static Map<String, dynamic> getVoiceConfig() {
    // Voice name may be configurable, but language, speaking rate and pitch are
    // intentionally hardcoded per project policy (do not use env to override).
    final voiceName = Config.get('GOOGLE_VOICE_NAME', 'es-ES-Neural2-A');
    final languageCode = resolveDefaultLanguageCode();
    final speakingRate = 1.0;
    final pitch = 0.0;

    return {'voiceName': voiceName, 'languageCode': languageCode, 'speakingRate': speakingRate, 'pitch': pitch};
  }

  /// Resolve a sensible default language code for Google TTS.
  /// Priority: provided country ISO2 -> LocaleUtils mapping -> system locale -> fallback 'es-ES'.
  static String resolveDefaultLanguageCode([String? countryIso2]) {
    try {
      if (countryIso2 != null && countryIso2.trim().isNotEmpty) {
        final codes = LocaleUtils.officialLanguageCodesForCountry(countryIso2.trim().toUpperCase());
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
