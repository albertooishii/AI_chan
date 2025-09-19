/// 🎯 DDD: Puerto para captura de audio para STT
/// El dominio define QUÉ necesita, la infraestructura CÓMO lo hace
abstract interface class IAudioRecorderService {
  /// Grabar audio por duración específica
  Future<AudioRecordingResult> recordAudio({
    required final Duration duration,
    final int sampleRate = 16000,
    final String format = 'wav',
  });

  /// Iniciar grabación continua
  Future<void> startRecording({
    final int sampleRate = 16000,
    final String format = 'wav',
  });

  /// Detener grabación y obtener resultado
  Future<AudioRecordingResult> stopRecording();

  /// Cancelar grabación sin obtener resultado
  Future<void> cancelRecording();

  /// Stream de datos de audio en tiempo real
  Stream<List<int>> get audioDataStream;

  /// Stream de amplitud/volumen del micrófono
  Stream<double> get amplitudeStream;

  /// Verificar si está grabando
  bool get isRecording;

  /// Verificar si los permisos están disponibles
  Future<bool> hasPermissions();

  /// Solicitar permisos de audio
  Future<bool> requestPermissions();

  /// Verificar disponibilidad del servicio
  Future<bool> isAvailable();
}

/// 🎯 DDD: Resultado de grabación de audio
class AudioRecordingResult {
  const AudioRecordingResult({
    required this.audioData,
    required this.format,
    required this.duration,
    required this.sampleRate,
    this.filePath,
  });

  final List<int> audioData;
  final String format;
  final Duration duration;
  final int sampleRate;
  final String? filePath; // Opcional: ruta del archivo temporal

  /// Tamaño del audio en bytes
  int get sizeInBytes => audioData.length;

  /// Duración estimada en segundos
  double get durationInSeconds => duration.inMilliseconds / 1000.0;

  @override
  String toString() =>
      'AudioRecordingResult($sizeInBytes bytes, ${durationInSeconds}s, $format)';
}

/// 🎯 DDD: Configuración de grabación
class AudioRecordingConfig {
  /// Configuración optimizada para transcripción STT
  factory AudioRecordingConfig.forSTT() {
    return const AudioRecordingConfig();
  }

  /// Configuración de alta calidad
  factory AudioRecordingConfig.highQuality() {
    return const AudioRecordingConfig(
      sampleRate: 44100,
      enableNoiseReduction: false, // Mantener calidad original
      enableEchoCancellation: false,
      enableAutoGainControl: false,
    );
  }
  const AudioRecordingConfig({
    this.sampleRate = 16000,
    this.format = 'wav',
    this.enableNoiseReduction = true,
    this.enableEchoCancellation = true,
    this.enableAutoGainControl = true,
  });

  final int sampleRate;
  final String format;
  final bool enableNoiseReduction;
  final bool enableEchoCancellation;
  final bool enableAutoGainControl;
}

/// 🎯 DDD: Excepciones específicas del grabador
class AudioRecorderException implements Exception {
  const AudioRecorderException(this.message, {this.originalError});

  final String message;
  final Object? originalError;

  @override
  String toString() => 'AudioRecorderException: $message';
}

/// 🎯 DDD: Excepciones de permisos
class AudioPermissionException extends AudioRecorderException {
  const AudioPermissionException(super.message, {super.originalError});
}
