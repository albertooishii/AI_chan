import 'package:ai_chan/shared.dart';

/// Voice information model for provider-agnostic voice representation
class VoiceInfo {
  const VoiceInfo({
    required this.id,
    required this.name,
    required this.language,
    required this.gender,
    this.description,
  });

  final String id;
  final String name;
  final String language;
  final String gender;
  final String? description;
}

/// Application service for managing TTS voice operations
/// Acts as a facade between presentation and infrastructure for voice-related operations
/// PROVIDER-AGNOSTIC: Uses dynamic AI provider system
class TtsVoiceManagementService {
  /// Constructor with dependency injection
  const TtsVoiceManagementService({
    required final AIProviderManager providerManager,
  }) : _providerManager = providerManager;
  final AIProviderManager _providerManager;

  /// Get available voices for all TTS providers

  Future<Map<String, List<Map<String, dynamic>>>> getAvailableVoices({
    final List<String>? languageCodes,
    final bool forceRefresh = false,
  }) async {
    try {
      await _providerManager.initialize();
      final Map<String, List<Map<String, dynamic>>> allVoices = {};

      // Get all providers that support TTS (audio generation)
      final ttsProviders = _providerManager.getProvidersByCapability(
        AICapability.audioGeneration,
      );

      for (final providerId in ttsProviders) {
        try {
          final provider = _providerManager.providers[providerId];
          if (provider != null) {
            // Check if provider has getAvailableVoices method (duck typing)
            if (provider is TTSVoiceProvider) {
              List<VoiceInfo> voices = [];

              voices = await (provider as TTSVoiceProvider)
                  .getAvailableVoices();

              // Filter by language codes if specified
              if (languageCodes != null && languageCodes.isNotEmpty) {
                voices = voices
                    .where(
                      (final voice) => languageCodes.contains(voice.language),
                    )
                    .toList();
              }

              // Convert to Map format
              allVoices[providerId] = voices
                  .map(
                    (final voice) => {
                      'id': voice.id,
                      'name': voice.name,
                      'language': voice.language,
                      'gender': voice.gender,
                      'description': voice.description ?? '',
                    },
                  )
                  .toList();
            } else {
              // Provider doesn't support voice enumeration
              allVoices[providerId] = [];
            }
          }
        } on Exception {
          // Provider failed, add empty list
          allVoices[providerId] = [];
        }
      }

      return allVoices;
    } on Exception {
      return {};
    }
  }

  /// Get available voices for a specific provider

  Future<List<Map<String, dynamic>>> getVoicesForProvider(
    final String providerId, {
    final List<String>? languageCodes,
    final bool forceRefresh = false,
  }) async {
    try {
      await _providerManager.initialize();
      final provider = _providerManager.providers[providerId];

      if (provider == null) {
        return [];
      }

      // Check if provider supports TTS (audio generation)
      if (!provider.supportsCapability(AICapability.audioGeneration)) {
        return [];
      }

      // Check if provider has getAvailableVoices method (duck typing)
      List<VoiceInfo> voices = [];

      if (provider is TTSVoiceProvider) {
        voices = await (provider as TTSVoiceProvider).getAvailableVoices();
      } else {
        return [];
      }

      // Filter by language codes if specified
      if (languageCodes != null && languageCodes.isNotEmpty) {
        voices = voices
            .where((final voice) => languageCodes.contains(voice.language))
            .toList();
      }

      // Convert to Map format
      return voices
          .map(
            (final voice) => {
              'id': voice.id,
              'name': voice.name,
              'language': voice.language,
              'gender': voice.gender,
              'description': voice.description ?? '',
            },
          )
          .toList();
    } on Exception {
      return [];
    }
  }

  /// Check if a specific provider is available

  Future<bool> isProviderAvailable(final String providerId) async {
    try {
      await _providerManager.initialize();
      final provider = _providerManager.providers[providerId];

      return provider != null &&
          provider.supportsCapability(AICapability.audioGeneration) &&
          await provider.isHealthy();
    } on Exception {
      return false;
    }
  }

  /// Get list of available TTS providers

  Future<List<String>> getAvailableProviders() async {
    try {
      await _providerManager.initialize();
      return _providerManager.getProvidersByCapability(
        AICapability.audioGeneration,
      );
    } on Exception {
      return [];
    }
  }

  /// Clear voices cache for all providers - Not supported by current provider system

  Future<void> clearVoicesCache() async {
    // Current provider system doesn't expose cache clearing for voices
    // This would need to be implemented at the provider level
  }

  /// Clear voices cache for specific provider - Not supported by current provider system

  Future<void> clearVoicesCacheForProvider(final String providerId) async {
    // Current provider system doesn't expose cache clearing for voices
    // This would need to be implemented at the provider level
  }

  /// Get cache size - Returns 0 as current provider system doesn't expose cache size

  Future<int> getCacheSize() async {
    return 0;
  }

  /// Clear audio cache - Not supported by current provider system

  Future<void> clearAudioCache() async {
    // Current provider system doesn't expose audio cache clearing
    // This would need to be implemented at the provider level
  }

  /// Format cache size for display

  String formatCacheSize(final int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).round()} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).round()} GB';
  }
}

/// Generic interface for providers that support voice enumeration
/// This is provider-agnostic and can be implemented by any provider
abstract interface class TTSVoiceProvider {
  Future<List<VoiceInfo>> getAvailableVoices();
}
