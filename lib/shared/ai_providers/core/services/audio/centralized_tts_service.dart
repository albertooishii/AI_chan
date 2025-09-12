import 'dart:convert';
import '../ai_provider_manager.dart';
import '../../models/ai_capability.dart';
import '../../../../utils/log_utils.dart';
import '../../../../utils/audio_duration_utils.dart';
import '../../interfaces/audio/i_tts_service.dart';
import '../../models/audio/synthesis_result.dart';
import '../../models/audio/voice_info.dart';
import '../../models/audio/voice_settings.dart';
import 'dart:io';
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

    final aiResponse = await audioCapabilityProvider.generateAudio(
      text: text,
      voice: settings.voiceId,
      additionalParams: {
        'speed': settings.speed,
        'pitch': settings.pitch,
        'response_format': 'mp3',
        'model': 'gpt-4o-mini-tts', // Especificar modelo explícitamente
      },
    );

    // Check if we have valid audio data
    if (aiResponse.base64.isEmpty) {
      throw VoiceSynthesisException(
        'No se recibió audio válido del provider: ${aiResponse.text}',
      );
    }

    Log.d(
      '[CentralizedTTS] ✅ Audio generado exitosamente: ${aiResponse.base64.length} chars base64',
    );

    final audioData = base64Decode(aiResponse.base64);

    // 🎯 Crear un archivo temporal para obtener la duración real
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tempDir.path}/tts_duration_check_${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
    await tempFile.writeAsBytes(audioData);

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
      audioData: audioData,
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
