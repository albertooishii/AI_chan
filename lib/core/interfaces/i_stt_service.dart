abstract class ISttService {
  /// Transcribe an audio file at [filePath] and return the transcription text or null on failure.
  Future<String?> transcribeAudio(final String filePath);

  /// Extended version with options for advanced use cases
  Future<String?> transcribeFile({
    required final String filePath,
    final Map<String, dynamic>? options,
  }) async {
    return await transcribeAudio(filePath);
  }
}
