abstract class ISttService {
  /// Transcribe an audio file at [path] and return the transcription text or null on failure.
  Future<String?> transcribeAudio(String path);
}
