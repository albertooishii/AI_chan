/// Formato de audio usado en las llamadas
class AudioFormat {
  const AudioFormat({
    this.sampleRate = 16000, // 16kHz por defecto (común para STT)
    this.channels = 1, // Mono por defecto
    this.bitsPerSample = 16, // 16 bits por defecto
    this.encoding = AudioEncoding.pcm,
  });

  /// Frecuencia de muestreo en Hz
  final int sampleRate;

  /// Número de canales (1 = mono, 2 = estéreo)
  final int channels;

  /// Bits por muestra (8, 16, 24, 32)
  final int bitsPerSample;

  /// Tipo de codificación
  final AudioEncoding encoding;

  /// Calcula el bitrate total
  int get bitrate => sampleRate * channels * bitsPerSample;

  /// Calcula bytes por segundo
  int get bytesPerSecond => bitrate ~/ 8;

  @override
  String toString() {
    return 'AudioFormat(${sampleRate}Hz, ${channels}ch, ${bitsPerSample}bit, $encoding)';
  }

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      other is AudioFormat &&
          runtimeType == other.runtimeType &&
          sampleRate == other.sampleRate &&
          channels == other.channels &&
          bitsPerSample == other.bitsPerSample &&
          encoding == other.encoding;

  @override
  int get hashCode =>
      sampleRate.hashCode ^
      channels.hashCode ^
      bitsPerSample.hashCode ^
      encoding.hashCode;
}

/// Tipos de codificación de audio soportados
enum AudioEncoding {
  /// Modulación por código de pulsos (sin compresión)
  pcm,

  /// MP3 comprimido
  mp3,

  /// Opus comprimido (recomendado para tiempo real)
  opus,

  /// WebM comprimido
  webm,
}
