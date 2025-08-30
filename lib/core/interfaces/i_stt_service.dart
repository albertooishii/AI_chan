abstract class ISttService {
  /// Transcribe an audio file at [filePath] and return the transcription text or null on failure.
  Future<String?> transcribeAudio(String filePath);

  /// Extended version with options for advanced use cases
  Future<String?> transcribeFile({required String filePath, Map<String, dynamic>? options}) async {
    return await transcribeAudio(filePath);
  }
}
