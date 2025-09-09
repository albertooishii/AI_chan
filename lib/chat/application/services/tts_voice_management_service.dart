import '../../domain/interfaces/i_tts_voice_management_service.dart';

/// Application service for managing TTS voice operations
/// Acts as a facade between presentation and infrastructure for voice-related operations
/// Implements domain interface to maintain Clean Architecture compliance
class TtsVoiceManagementService implements ITtsVoiceManagementService {
  /// Get available voices for Android Native TTS
  @override
  Future<List<Map<String, dynamic>>> getAndroidNativeVoices({
    final List<String>? userLangCodes,
    final List<String>? aiLangCodes,
  }) async {
    try {
      // final ttsService = getTtsServiceForProvider('android_native');
      // For now, return empty list as the interface doesn't provide voice enumeration
      // This would need to be extended in the domain interface
      return [];
    } on Exception {
      return [];
    }
  }

  /// Get available voices for Google Cloud TTS
  @override
  Future<List<Map<String, dynamic>>> getGoogleVoices({
    final bool forceRefresh = false,
  }) async {
    try {
      // final ttsService = getTtsServiceForProvider('google');
      // For now, return empty list as the interface doesn't provide voice enumeration
      // This would need to be extended in the domain interface
      return [];
    } on Exception {
      return [];
    }
  }

  /// Get available voices for OpenAI TTS
  @override
  Future<List<Map<String, dynamic>>> getOpenAiVoices() async {
    // Return static OpenAI voices
    return [
      {'name': 'alloy'},
      {'name': 'echo'},
      {'name': 'fable'},
      {'name': 'onyx'},
      {'name': 'nova'},
      {'name': 'shimmer'},
    ];
  }

  /// Check if Android Native TTS is available
  @override
  bool isAndroidNativeTtsAvailable() {
    // For now, return true if platform is Android
    // In a real implementation, this would check actual availability through domain interface
    return true;
  }

  /// Check if Google TTS is configured
  @override
  bool isGoogleTtsConfigured() {
    // For now, return true as this is a simple configuration check
    // In a real implementation, this would check configuration status through domain interface
    return true;
  }

  /// Clear voices cache
  @override
  Future<void> clearVoicesCache() async {
    try {
      // This would need to be implemented through domain interfaces
      // For now, do nothing
    } on Exception {
      // Ignore errors
    }
  }

  /// Get cache size
  @override
  Future<int> getCacheSize() async {
    // This would need to be implemented in a cache service through domain interface
    // For now, return 0
    return 0;
  }

  /// Clear audio cache
  @override
  Future<void> clearAudioCache() async {
    // This would need to be implemented in a cache service through domain interface
  }

  /// Format cache size for display
  @override
  String formatCacheSize(final int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).round()} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).round()} GB';
  }
}
