/// 🎯 **Chat Audio Utils Service Interface** - Domain Abstraction for Audio Utilities
///
/// Defines the contract for audio utility operations within the chat bounded context.
/// This ensures bounded context isolation while providing audio processing utilities.
///
/// **Clean Architecture Compliance:**
/// ✅ Chat domain defines its own interfaces
/// ✅ No direct dependencies on shared context
/// ✅ Bounded context isolation maintained
abstract class IChatAudioUtilsService {
  /// Calculates audio duration from file path
  Future<Duration?> getAudioDuration(final String filePath);

  /// Formats duration to human-readable string
  String formatDuration(final Duration duration);

  /// Validates audio file format
  bool isValidAudioFormat(final String filePath);
}
