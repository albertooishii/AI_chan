/// 🎵 Excepciones relacionadas con reproducción de audio
class AudioPlaybackException implements Exception {
  const AudioPlaybackException(this.message, {this.originalError});

  final String message;
  final dynamic originalError;

  @override
  String toString() {
    if (originalError != null) {
      return 'AudioPlaybackException: $message (Original: $originalError)';
    }
    return 'AudioPlaybackException: $message';
  }
}

/// Excepción específica para errores de archivo
class AudioFileException extends AudioPlaybackException {
  const AudioFileException(super.message, {super.originalError});
}

/// Excepción específica para errores de duración
class AudioDurationException extends AudioPlaybackException {
  const AudioDurationException(super.message, {super.originalError});
}

/// Excepción específica para errores de formato
class AudioFormatException extends AudioPlaybackException {
  const AudioFormatException(super.message, {super.originalError});
}
