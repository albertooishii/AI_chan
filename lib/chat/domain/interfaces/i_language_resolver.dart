/// Interface for resolving language codes from voice names
/// Used by TTS service to automatically detect language codes for TTS voices
abstract class ILanguageResolver {
  /// Resolve the language code for a given voice name
  /// Returns the appropriate language code or a fallback if resolution fails
  Future<String> resolveLanguageCode(String voiceName);
}
