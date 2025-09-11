import '../value_objects/voice_settings.dart';

/// 🎯 DDD: Puerto para síntesis de voz (TTS)
/// El dominio define QUÉ necesita, la infraestructura CÓMO lo hace
abstract interface class ITextToSpeechService {
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
}

/// 🎯 DDD: Puerto para reconocimiento de voz (STT)
abstract interface class ISpeechToTextService {
  /// Iniciar escucha en tiempo real
  Stream<RecognitionResult> startListening({
    required final String language,
    final bool enablePartialResults = true,
  });

  /// Detener escucha
  Future<void> stopListening();

  /// Reconocer audio desde datos
  Future<RecognitionResult> recognizeAudio({
    required final List<int> audioData,
    required final String language,
    final String format = 'wav',
  });

  /// Verificar disponibilidad
  Future<bool> isAvailable();

  /// Idiomas soportados
  Future<List<String>> getSupportedLanguages();

  /// ¿Está escuchando actualmente?
  bool get isListening;
}

/// 🎯 DDD: Resultado de síntesis
class SynthesisResult {
  const SynthesisResult({
    required this.audioData,
    required this.format,
    required this.duration,
    required this.settings,
  });

  final List<int> audioData;
  final String format;
  final Duration duration;
  final VoiceSettings settings;

  @override
  String toString() =>
      'SynthesisResult(${audioData.length} bytes, $format, ${duration.inMilliseconds}ms)';
}

/// 🎯 DDD: Resultado de reconocimiento
class RecognitionResult {
  const RecognitionResult({
    required this.text,
    required this.confidence,
    required this.isFinal,
    required this.duration,
  });

  final String text;
  final double confidence;
  final bool isFinal;
  final Duration duration;

  @override
  String toString() =>
      'RecognitionResult("$text", confidence: $confidence, final: $isFinal)';
}

/// 🎯 DDD: Info de voz disponible
class VoiceInfo {
  const VoiceInfo({
    required this.id,
    required this.name,
    required this.language,
    required this.gender,
    this.description,
  });

  final String id;
  final String name;
  final String language;
  final VoiceGender gender;
  final String? description;

  @override
  String toString() => 'VoiceInfo($id: $name, $language, $gender)';
}

/// 🎯 DDD: Género de voz
enum VoiceGender { male, female, neutral, unknown }

extension VoiceGenderExtension on VoiceGender {
  String get displayName {
    switch (this) {
      case VoiceGender.male:
        return 'Masculina';
      case VoiceGender.female:
        return 'Femenina';
      case VoiceGender.neutral:
        return 'Neutral';
      case VoiceGender.unknown:
        return 'Desconocido';
    }
  }
}
