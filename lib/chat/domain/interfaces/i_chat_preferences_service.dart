/// Domain interface for chat-related preferences in the chat bounded context.
///
/// This abstraction allows the chat application layer to access user preferences
/// without depending directly on shared infrastructure implementations.
/// Following DDD principles and bounded context isolation.
abstract class IChatPreferencesService {
  /// Gets the user's preferred TTS voice, with fallback if not set.
  ///
  /// [fallback] - Default voice to return if no preference is stored
  /// Returns the preferred voice name or the fallback value
  Future<String> getPreferredVoice({final String fallback = 'nova'});
}
