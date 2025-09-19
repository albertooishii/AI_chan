/// Factory for creating AI Providers based on YAML configuration.
/// This factory uses the configuration loaded from YAML files to instantiate
/// the appropriate provider implementations dynamically.
library;

import 'package:ai_chan/shared.dart';
import 'package:ai_chan/shared/ai_providers/core/registry/provider_auto_registry.dart';

/// Exception thrown when provider creation fails
class ProviderCreationException implements Exception {
  const ProviderCreationException(this.message, [this.cause]);

  final String message;
  final dynamic cause;

  @override
  String toString() =>
      'ProviderCreationException: $message${cause != null ? ' (Caused by: $cause)' : ''}';
}

/// Factory for creating AI Providers from configuration
class AIProviderFactory {
  static final Map<String, IAIProvider> _providerCache = {};

  /// Create a provider instance from configuration using dynamic registry
  static IAIProvider createProvider(
    final String providerId,
    final ProviderConfig config,
  ) {
    try {
      // Check cache first
      if (_providerCache.containsKey(providerId)) {
        return _providerCache[providerId]!;
      }

      Log.i('Creating provider: $providerId');

      // Try to create provider using dynamic registry
      final provider = ProviderAutoRegistry.createProvider(providerId, config);

      if (provider == null) {
        throw ProviderCreationException(
          'No registered constructor found for provider type: $providerId. '
          'Make sure the provider is registered in provider_registration.dart',
        );
      }

      // Cache the provider
      _providerCache[providerId] = provider;

      Log.i('Successfully created provider: $providerId');
      return provider;
    } on Exception catch (e) {
      Log.e('Failed to create provider $providerId: $e');
      if (e is ProviderCreationException) {
        rethrow;
      }
      throw ProviderCreationException(
        'Failed to create provider: $providerId',
        e,
      );
    }
  }

  /// Create multiple providers from configuration
  static Future<Map<String, IAIProvider>> createProviders(
    final Map<String, ProviderConfig> configs,
  ) async {
    final providers = <String, IAIProvider>{};

    for (final entry in configs.entries) {
      final providerId = entry.key;
      final config = entry.value;

      if (!config.enabled) {
        Log.d('Skipping disabled provider: $providerId');
        continue;
      }

      try {
        final provider = createProvider(providerId, config);

        // Initialize the provider after creation
        Log.d('Initializing provider: $providerId');
        final initialized = await provider.initialize({});

        if (initialized) {
          providers[providerId] = provider;
          Log.d('Provider $providerId initialized successfully');
        } else {
          Log.w('Provider $providerId failed to initialize, skipping');
        }
      } on Exception catch (e) {
        Log.e('Failed to create/initialize provider $providerId, skipping: $e');
        // Continue with other providers even if one fails
      }
    }

    Log.i(
      'Created and initialized ${providers.length} providers: ${providers.keys.join(', ')}',
    );
    return providers;
  }

  /// Clear the provider cache
  static void clearCache() {
    _providerCache.clear();
    Log.d('Provider cache cleared');
  }

  /// Get a cached provider if available
  static IAIProvider? getCachedProvider(final String providerId) {
    return _providerCache[providerId];
  }

  /// Get available provider types that can be created (now dynamic)
  static List<String> getAvailableProviderTypes() {
    return ProviderAutoRegistry.getRegisteredProviders();
  }

  /// Check if a provider type is supported (now dynamic)
  static bool isProviderTypeSupported(final String providerId) {
    return ProviderAutoRegistry.isProviderRegistered(providerId);
  }
}
