/// Domain interface for TTS voice management operations
/// Defines the contract for voice-related operations in the chat bounded context
abstract interface class ITtsVoiceManagementService {
  /// Get available voices for Android Native TTS
  Future<List<Map<String, dynamic>>> getAndroidNativeVoices({
    final List<String>? userLangCodes,
    final List<String>? aiLangCodes,
  });

  /// Get available voices for Google Cloud TTS
  Future<List<Map<String, dynamic>>> getGoogleVoices({
    final bool forceRefresh = false,
  });

  /// Get available voices for OpenAI TTS
  Future<List<Map<String, dynamic>>> getOpenAiVoices();

  /// Check if Android Native TTS is available
  bool isAndroidNativeTtsAvailable();

  /// Check if Google TTS is configured
  bool isGoogleTtsConfigured();

  /// Clear voices cache
  Future<void> clearVoicesCache();

  /// Get cache size
  Future<int> getCacheSize();

  /// Clear audio cache
  Future<void> clearAudioCache();

  /// Format cache size for display
  String formatCacheSize(final int bytes);
}
