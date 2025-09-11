import '../../domain/interfaces/voice_services.dart';
import '../../domain/value_objects/voice_settings.dart';

/// 🎯 DDD: Adaptador de infraestructura para TTS dinámico
/// Usa AIProviderManager para resolver providers automáticamente
class DynamicTextToSpeechService implements ITextToSpeechService {
  DynamicTextToSpeechService._();

  static final DynamicTextToSpeechService _instance =
      DynamicTextToSpeechService._();
  static DynamicTextToSpeechService get instance => _instance;

  @override
  Future<SynthesisResult> synthesize({
    required final String text,
    required final VoiceSettings settings,
  }) async {
    try {
      // TODO: Integrar con AIProviderManager cuando tenga capacidad TTS
      // Por ahora simulamos la respuesta

      // Simular latencia realista
      await Future.delayed(Duration(milliseconds: text.length * 50));

      // Simular datos de audio (en implementación real vendrían del provider)
      final audioData = List.generate(1000, (final i) => i % 256);

      return SynthesisResult(
        audioData: audioData,
        format: 'wav',
        duration: Duration(milliseconds: text.length * 100),
        settings: settings,
      );
    } on Exception catch (e) {
      throw VoiceSynthesisException('Error en síntesis: $e');
    }
  }

  @override
  Future<List<VoiceInfo>> getAvailableVoices({
    required final String language,
  }) async {
    // TODO: Obtener de AIProviderManager dinámicamente
    // Por ahora devolvemos voces simuladas

    return [
      VoiceInfo(
        id: 'alloy',
        name: 'Alloy',
        language: language,
        gender: VoiceGender.neutral,
        description: 'Voz neural equilibrada',
      ),
      VoiceInfo(
        id: 'echo',
        name: 'Echo',
        language: language,
        gender: VoiceGender.male,
        description: 'Voz masculina clara',
      ),
      VoiceInfo(
        id: 'nova',
        name: 'Nova',
        language: language,
        gender: VoiceGender.female,
        description: 'Voz femenina natural',
      ),
    ];
  }

  @override
  Future<bool> isAvailable() async {
    // TODO: Verificar con AIProviderManager si hay providers con TTS
    // Por ahora simulamos disponibilidad
    return true;
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

/// 🎯 DDD: Adaptador de infraestructura para STT dinámico
class DynamicSpeechToTextService implements ISpeechToTextService {
  DynamicSpeechToTextService._();

  static final DynamicSpeechToTextService _instance =
      DynamicSpeechToTextService._();
  static DynamicSpeechToTextService get instance => _instance;

  bool _isListening = false;

  @override
  Stream<RecognitionResult> startListening({
    required final String language,
    final bool enablePartialResults = true,
  }) async* {
    if (_isListening) {
      throw const SpeechRecognitionException('Ya está escuchando');
    }

    _isListening = true;

    try {
      // TODO: Integrar con AIProviderManager para STT real
      // Por ahora simulamos reconocimiento

      yield const RecognitionResult(
        text: 'Simulando reconocimiento...',
        confidence: 0.5,
        isFinal: false,
        duration: Duration(milliseconds: 500),
      );

      await Future.delayed(const Duration(seconds: 2));

      yield const RecognitionResult(
        text: 'Texto reconocido de ejemplo',
        confidence: 0.95,
        isFinal: true,
        duration: Duration(seconds: 2),
      );
    } finally {
      _isListening = false;
    }
  }

  @override
  Future<void> stopListening() async {
    _isListening = false;
  }

  @override
  Future<RecognitionResult> recognizeAudio({
    required final List<int> audioData,
    required final String language,
    final String format = 'wav',
  }) async {
    // TODO: Integrar con AIProviderManager
    await Future.delayed(const Duration(milliseconds: 500));

    return RecognitionResult(
      text: 'Texto reconocido desde audio (${audioData.length} bytes)',
      confidence: 0.92,
      isFinal: true,
      duration: Duration(
        milliseconds: audioData.length ~/ 16,
      ), // Aprox para 16kHz
    );
  }

  @override
  Future<bool> isAvailable() async {
    // TODO: Verificar con AIProviderManager
    return true;
  }

  @override
  Future<List<String>> getSupportedLanguages() async {
    // TODO: Obtener de AIProviderManager
    return ['es-ES', 'en-US', 'fr-FR', 'de-DE', 'it-IT', 'pt-BR'];
  }

  @override
  bool get isListening => _isListening;
}

/// 🎯 DDD: Excepciones específicas
class VoiceSynthesisException implements Exception {
  const VoiceSynthesisException(this.message);
  final String message;

  @override
  String toString() => 'VoiceSynthesisException: $message';
}

class SpeechRecognitionException implements Exception {
  const SpeechRecognitionException(this.message);
  final String message;

  @override
  String toString() => 'SpeechRecognitionException: $message';
}
