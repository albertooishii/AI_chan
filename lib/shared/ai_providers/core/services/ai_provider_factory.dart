/// Factory for creating AI Providers based on YAML configuration.
/// This factory uses the configuration loaded from YAML files to instantiate
/// the appropriate provider implementations.
library;

import 'package:ai_chan/shared/ai_providers/core/interfaces/i_ai_provider.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_provider_config.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_provider_metadata.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/shared/ai_providers/implementations/openai_provider.dart';
import 'package:ai_chan/shared/ai_providers/implementations/google_provider.dart';
import 'package:ai_chan/shared/ai_providers/implementations/xai_provider.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

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

  /// Create a provider instance from configuration
  static IAIProvider createProvider(final String providerId, final ProviderConfig config) {
    try {
      // Check cache first
      if (_providerCache.containsKey(providerId)) {
        return _providerCache[providerId]!;
      }

      Log.i('Creating provider: $providerId');

      IAIProvider provider;

      // Create provider based on ID
      switch (providerId.toLowerCase()) {
        case 'openai':
          provider = _createOpenAIProvider(config);
          break;
        case 'google':
          provider = _createGoogleProvider(config);
          break;
        case 'xai':
          provider = _createXAIProvider(config);
          break;
        default:
          throw ProviderCreationException(
            'Unsupported provider type: $providerId',
          );
      }

      // Cache the provider
      _providerCache[providerId] = provider;

      Log.i('Successfully created provider: $providerId');
      return provider;
    } catch (e) {
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
  static Map<String, IAIProvider> createProviders(
    final Map<String, ProviderConfig> configs,
  ) {
    final providers = <String, IAIProvider>{};

    for (final entry in configs.entries) {
      final providerId = entry.key;
      final config = entry.value;

      if (!config.enabled) {
        Log.d('Skipping disabled provider: $providerId');
        continue;
      }

      try {
        providers[providerId] = createProvider(providerId, config);
      } catch (e) {
        Log.e('Failed to create provider $providerId, skipping: $e');
        // Continue with other providers even if one fails
      }
    }

    Log.i(
      'Created ${providers.length} providers: ${providers.keys.join(', ')}',
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

  /// Create OpenAI provider with configuration
  static IAIProvider _createOpenAIProvider(final ProviderConfig config) {
    // Create metadata from configuration
    final metadata = AIProviderMetadata(
      providerId: 'openai',
      providerName: config.displayName,
      company: 'OpenAI',
      version: '1.0.0',
      description: config.description,
      supportedCapabilities: config.capabilities,
      defaultModels: config.defaults,
      availableModels: config.models,
      rateLimits: {
        'requests_per_minute': config.rateLimits.requestsPerMinute,
        'tokens_per_minute': config.rateLimits.tokensPerMinute,
      },
      requiresAuthentication: true,
      requiredConfigKeys: config.apiSettings.requiredEnvKeys,
      maxContextTokens: config.configuration.maxContextTokens,
      maxOutputTokens: config.configuration.maxOutputTokens,
      supportsStreaming: config.configuration.supportsStreaming,
      supportsFunctionCalling: config.configuration.supportsFunctionCalling,
    );

    return OpenAIProvider();
  }

  /// Create Google provider with configuration
  static IAIProvider _createGoogleProvider(final ProviderConfig config) {
    // Create metadata from configuration
    final metadata = AIProviderMetadata(
      providerId: 'google',
      providerName: config.displayName,
      company: 'Google',
      version: '1.0.0',
      description: config.description,
      supportedCapabilities: config.capabilities,
      defaultModels: config.defaults,
      availableModels: config.models,
      rateLimits: {
        'requests_per_minute': config.rateLimits.requestsPerMinute,
        'tokens_per_minute': config.rateLimits.tokensPerMinute,
      },
      requiresAuthentication: true,
      requiredConfigKeys: config.apiSettings.requiredEnvKeys,
      maxContextTokens: config.configuration.maxContextTokens,
      maxOutputTokens: config.configuration.maxOutputTokens,
      supportsStreaming: config.configuration.supportsStreaming,
      supportsFunctionCalling: config.configuration.supportsFunctionCalling,
    );

    return GoogleProvider();
  }

  /// Create X.AI provider with configuration
  static IAIProvider _createXAIProvider(final ProviderConfig config) {
    // Create metadata from configuration
    final metadata = AIProviderMetadata(
      providerId: 'xai',
      providerName: config.displayName,
      company: 'X.AI',
      version: '1.0.0',
      description: config.description,
      supportedCapabilities: config.capabilities,
      defaultModels: config.defaults,
      availableModels: config.models,
      rateLimits: {
        'requests_per_minute': config.rateLimits.requestsPerMinute,
        'tokens_per_minute': config.rateLimits.tokensPerMinute,
      },
      requiresAuthentication: true,
      requiredConfigKeys: config.apiSettings.requiredEnvKeys,
      maxContextTokens: config.configuration.maxContextTokens,
      maxOutputTokens: config.configuration.maxOutputTokens,
      supportsStreaming: config.configuration.supportsStreaming,
      supportsFunctionCalling: config.configuration.supportsFunctionCalling,
    );

    return XAIProvider();
  }

  /// Validate that all required providers for fallback chains can be created
  static List<String> validateFallbackChains(
    final Map<String, ProviderConfig> providerConfigs,
    final Map<AICapability, FallbackChain> fallbackChains,
  ) {
    final errors = <String>[];

    for (final entry in fallbackChains.entries) {
      final capability = entry.key;
      final chain = entry.value;

      // Check primary provider
      if (!providerConfigs.containsKey(chain.primary)) {
        errors.add(
          'Primary provider ${chain.primary} for ${capability.name} not found in configuration',
        );
      } else if (!providerConfigs[chain.primary]!.enabled) {
        errors.add(
          'Primary provider ${chain.primary} for ${capability.name} is disabled',
        );
      }

      // Check fallback providers
      for (final fallbackId in chain.fallbacks) {
        if (!providerConfigs.containsKey(fallbackId)) {
          errors.add(
            'Fallback provider $fallbackId for ${capability.name} not found in configuration',
          );
        } else if (!providerConfigs[fallbackId]!.enabled) {
          errors.add(
            'Fallback provider $fallbackId for ${capability.name} is disabled',
          );
        }
      }
    }

    return errors;
  }

  /// Test provider creation without caching
  static Future<bool> testProviderCreation(
    final String providerId,
    final ProviderConfig config,
  ) async {
    try {
      final provider = createProvider(providerId, config);

      // Try to initialize the provider
      final initialized = await provider.initialize({});

      if (!initialized) {
        Log.w('Provider $providerId failed to initialize');
        return false;
      }

      // Test health check if available
      final healthy = await provider.isHealthy();

      if (!healthy) {
        Log.w('Provider $providerId failed health check');
        return false;
      }

      Log.i('Provider $providerId passed creation and health tests');
      return true;
    } catch (e) {
      Log.e('Provider $providerId failed creation test: $e');
      return false;
    }
  }

  /// Get available provider types that can be created
  static List<String> getAvailableProviderTypes() {
    return ['openai', 'google', 'xai'];
  }

  /// Check if a provider type is supported
  static bool isProviderTypeSupported(final String providerId) {
    return getAvailableProviderTypes().contains(providerId.toLowerCase());
  }
}
