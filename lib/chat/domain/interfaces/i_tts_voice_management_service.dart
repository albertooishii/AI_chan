/// Domain interface for TTS voice management operations
/// Defines the contract for voice-related operations in the chat bounded context
/// PROVIDER-AGNOSTIC: No hardcoding of specific providers
abstract interface class ITtsVoiceManagementService {
  /// Get available voices for any TTS provider
  /// Returns voices categorized by provider type
  Future<Map<String, List<Map<String, dynamic>>>> getAvailableVoices({
    final List<String>? languageCodes,
    final bool forceRefresh = false,
  });

  /// Get available voices for a specific provider
  Future<List<Map<String, dynamic>>> getVoicesForProvider(
    final String providerId, {
    final List<String>? languageCodes,
    final bool forceRefresh = false,
  });

  /// Check if a specific provider is available
  Future<bool> isProviderAvailable(final String providerId);

  /// Get list of available TTS providers
  Future<List<String>> getAvailableProviders();

  /// Clear voices cache for all providers
  Future<void> clearVoicesCache();

  /// Clear voices cache for specific provider
  Future<void> clearVoicesCacheForProvider(final String providerId);

  /// Get cache size
  Future<int> getCacheSize();

  /// Clear audio cache
  Future<void> clearAudioCache();

  /// Format cache size for display
  String formatCacheSize(final int bytes);
}
