import 'package:ai_chan/shared.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// 🎯 Servicio centralizado de TTS (Text-to-Speech)
/// Usa AIProviderManager para resolver providers automáticamente
class CentralizedTtsService implements ITtsService {
  CentralizedTtsService._();

  static final CentralizedTtsService _instance = CentralizedTtsService._();
  static CentralizedTtsService get instance => _instance;

  final AIProviderManager _aiProviderManager = AIProviderManager.instance;

  @override
  Future<SynthesisResult> synthesize({
    required final String text,
    required final VoiceSettings settings,
  }) async {
    Log.d(
      '[CentralizedTTS] 🎯 Intentando obtener provider para audio generation...',
    );

    final audioCapabilityProvider = await _aiProviderManager
        .getProviderForCapability(AICapability.audioGeneration);

    if (audioCapabilityProvider == null) {
      throw const VoiceSynthesisException(
        'No hay provider de audio disponible',
      );
    }

    Log.d(
      '[CentralizedTTS] ✅ Provider encontrado: ${audioCapabilityProvider.providerId}',
    );

    final providerResp = await audioCapabilityProvider.generateAudio(
      text: text,
      voice: settings.voiceId,
      additionalParams: {
        'speed': settings.speed,
        'pitch': settings.pitch,
        'response_format': 'mp3',
        'model': 'gpt-4o-mini-tts', // Especificar modelo explícitamente
      },
    );

    // ProviderResponse exposes semantic fields directly. Providers may return
    // either `audioBase64` (preferred) or legacy pre-persisted filenames.
    String? audioFileName;
    Uint8List? audioBytes;

    if (providerResp.audioBase64 != null &&
        providerResp.audioBase64!.isNotEmpty) {
      // Persist base64 audio centrally and load bytes
      try {
        final saved = await AudioPersistenceService.instance.saveBase64Audio(
          providerResp.audioBase64!,
          prefix: 'tts',
        );
        if (saved != null && saved.isNotEmpty) {
          audioFileName = saved;
        }
      } on Exception catch (e) {
        Log.w('[CentralizedTTS] Failed to persist provider audio: $e');
      }
    }

    // If the provider returned a filename (legacy), prefer it
    if (audioFileName == null && providerResp.audioBase64 == null) {
      // No base64 provided; there is no filename concept anymore from providers
      // so fail fast with a helpful message
      throw VoiceSynthesisException(
        'No se recibió audio válido del provider: ${providerResp.text}',
      );
    }

    if (audioFileName != null) {
      Log.d(
        '[CentralizedTTS] Loading persisted audio from file: $audioFileName',
      );
      final loaded = await AudioPersistenceService.instance.loadAudioAsBytes(
        audioFileName,
      );
      audioBytes = loaded == null ? null : Uint8List.fromList(loaded);
    }
    if (audioBytes == null || audioBytes.isEmpty) {
      throw VoiceSynthesisException(
        'No se pudo cargar el audio persistido: $audioFileName',
      );
    }

    // 🎯 Crear un archivo temporal para obtener la duración real
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tempDir.path}/tts_duration_check_${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
    await tempFile.writeAsBytes(audioBytes);

    // Obtener duración real del archivo
    Duration realDuration;
    try {
      final duration = await AudioDurationUtils.getAudioDuration(tempFile.path);
      realDuration =
          duration ??
          _calculateRealisticDuration(
            text,
            settings.speed,
          ); // Fallback mejorado
      Log.d(
        '[CentralizedTTS] 🎵 Duración real obtenida: ${realDuration.inMilliseconds}ms',
      );
    } on Exception catch (durationError) {
      Log.w(
        '[CentralizedTTS] ⚠️ Error obteniendo duración real: $durationError',
      );
      realDuration = _calculateRealisticDuration(
        text,
        settings.speed,
      ); // Fallback mejorado
    } finally {
      // Limpiar archivo temporal
      try {
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
        }
      } on Exception catch (_) {
        // Ignorar errores de limpieza
      }
    }

    return SynthesisResult(
      audioData: audioBytes,
      format: 'mp3',
      duration: realDuration,
      settings: settings,
    );
  }

  /// Calcula una duración realista basada en velocidad de lectura TTS
  Duration _calculateRealisticDuration(final String text, final double speed) {
    final words = text
        .split(RegExp(r'\s+'))
        .where((final word) => word.isNotEmpty)
        .length;
    final baseWpm = 175.0; // Palabras por minuto base para TTS
    final adjustedWpm = baseWpm * speed; // Ajustar por velocidad configurada
    final durationMinutes = words / adjustedWpm;
    return Duration(milliseconds: (durationMinutes * 60 * 1000).round());
  }

  @override
  Future<List<VoiceInfo>> getAvailableVoices({
    required final String language,
  }) async {
    // ✅ CORRECTO: Obtener voces del provider activo dinámicamente
    // Cada provider (OpenAI, Google, XAI) expone sus propias voces

    final provider = await _aiProviderManager.getProviderForCapability(
      AICapability.audioGeneration,
    );
    if (provider != null) {
      try {
        // Cast al provider concreto para acceder a getAvailableVoices()
        final concreteProvider = provider as dynamic;

        // Verificar que el provider tenga el método usando try-catch en lugar de hasMethod
        final voices = await concreteProvider.getAvailableVoices() as List;

        Log.d(
          '[CentralizedTTS] ✅ Voces obtenidas del provider ${provider.providerId}: ${voices.length} voces',
        );
        return voices.cast<VoiceInfo>();
      } on Object catch (e) {
        Log.w(
          '[CentralizedTTS] Error getting voices from provider ${provider.providerId}: $e',
        );
      }
    } else {
      Log.w('[CentralizedTTS] No hay provider de audio disponible');
    }

    // Fallback: retornar lista vacía si no se puede obtener del provider
    Log.d('[CentralizedTTS] ⚠️ Usando fallback - lista vacía de voces');
    return [];
  }

  @override
  Future<bool> isAvailable() async {
    try {
      final audioCapabilityProvider = await _aiProviderManager
          .getProviderForCapability(AICapability.audioGeneration);
      return audioCapabilityProvider != null;
    } on Exception catch (e) {
      Log.w('[CentralizedTTS] Error verificando disponibilidad: $e');
      return false;
    }
  }

  @override
  Future<List<String>> getSupportedLanguages() async {
    // TODO: Obtener de AIProviderManager dinámicamente
    return ['es-ES', 'en-US', 'fr-FR', 'de-DE', 'it-IT', 'pt-BR'];
  }

  @override
  Future<String?> synthesizeToFile({
    required final String text,
    final Map<String, dynamic>? options,
  }) async {
    try {
      Log.d('[CentralizedTTS] Sintetizando texto a archivo: $text');

      // Crear configuración de voz con opciones o defaults
      final voiceId = options?['voiceId'] as String? ?? 'es-ES-Standard-A';
      final language = options?['language'] as String? ?? 'es-ES';

      final settings = VoiceSettings.create(
        voiceId: voiceId,
        language: language,
      );

      // Sintetizar audio
      final result = await synthesize(text: text, settings: settings);

      if (result.audioData.isEmpty) {
        Log.w('[CentralizedTTS] No se generó audio para: $text');
        return null;
      }

      // Convertir bytes a base64 y guardar
      final audioBase64 = base64Encode(result.audioData);
      final savedFileName = await AudioPersistenceService.instance
          .saveBase64Audio(audioBase64, prefix: 'tts');

      if (savedFileName != null) {
        // Construir ruta completa
        final dir =
            await getTemporaryDirectory(); // Usar temp directory como fallback
        final filePath = '${dir.path}/$savedFileName';
        Log.d('[CentralizedTTS] ✅ Audio guardado en: $filePath');
        return filePath;
      } else {
        Log.w('[CentralizedTTS] Error guardando archivo de audio');
        return null;
      }
    } on Exception catch (e) {
      Log.e('[CentralizedTTS] Error sintetizando a archivo: $e');
      return null;
    }
  }

  @override
  Future<SynthesisResult> previewVoice({
    required final String voiceId,
    required final String language,
    final String sampleText = 'Hola, esta es una prueba de voz.',
  }) async {
    final settings = VoiceSettings.create(voiceId: voiceId, language: language);
    return synthesize(text: sampleText, settings: settings);
  }
}

/// 🎯 DDD: Excepciones específicas
class VoiceSynthesisException implements Exception {
  const VoiceSynthesisException(this.message);
  final String message;

  @override
  String toString() => 'VoiceSynthesisException: $message';
}
