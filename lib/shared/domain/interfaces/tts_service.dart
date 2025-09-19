import 'package:ai_chan/shared/ai_providers/core/models/audio/synthesis_result.dart';
import 'package:ai_chan/shared/ai_providers/core/models/audio/voice_info.dart';
import 'package:ai_chan/shared/ai_providers/core/models/audio/voice_settings.dart';

// Re-export types so interface users can access them
export 'package:ai_chan/shared/ai_providers/core/models/audio/synthesis_result.dart';
export 'package:ai_chan/shared/ai_providers/core/models/audio/voice_info.dart';
export 'package:ai_chan/shared/ai_providers/core/models/audio/voice_settings.dart';

/// 🎯 DDD: Puerto para síntesis de voz (TTS)
/// El dominio define QUÉ necesita, la infraestructura CÓMO lo hace
abstract interface class ITtsService {
  /// Sintetizar texto a audio
  Future<SynthesisResult> synthesize({
    required final String text,
    required final VoiceSettings settings,
  });

  /// Obtener voces disponibles para un idioma
  Future<List<VoiceInfo>> getAvailableVoices({required final String language});

  /// Verificar si el servicio está disponible
  Future<bool> isAvailable();

  /// Obtener idiomas soportados
  Future<List<String>> getSupportedLanguages();

  /// Previsualizar voz (para configuración)
  Future<SynthesisResult> previewVoice({
    required final String voiceId,
    required final String language,
    final String sampleText = 'Hola, esta es una prueba de voz.',
  });

  /// Genera un archivo de audio para el texto y devuelve la ruta local.
  /// (Método legacy mantenido para compatibilidad)
  Future<String?> synthesizeToFile({
    required final String text,
    final Map<String, dynamic>? options,
  });
}
