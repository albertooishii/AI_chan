import 'package:ai_chan/shared.dart'; // Consolidated import

/// Central registry for all AI providers in the dynamic provider system.
///
/// This registry provides the new plugin architecture interface.
class AIProviderRegistry {
  AIProviderRegistry._internal();
  factory AIProviderRegistry() => _instance;
  static final AIProviderRegistry _instance = AIProviderRegistry._internal();

  final Map<String, IAIProvider> _providers = {};
  final Map<String, bool> _initialized = {};

  /// Initialize the registry with providers from configuration
  Future<void> initialize() async {
    try {
      // Load configuration dynamically
      final config = await AIProviderConfigLoader.loadDefault();
      int successCount = 0;
      int totalCount = 0;

      Log.i('[AIProviderRegistry] Loading providers from configuration...');

      // Register each enabled provider from config
      for (final entry in config.aiProviders.entries) {
        final providerId = entry.key;
        final providerConfig = entry.value;
        totalCount++;

        if (!providerConfig.enabled) {
          Log.i('[AIProviderRegistry] Skipping disabled provider: $providerId');
          continue;
        }

        try {
          // Create provider dynamically using factory
          final provider = AIProviderFactory.createProvider(
            providerId,
            providerConfig,
          );

          final success = await registerProvider(provider);
          if (success) {
            successCount++;
            Log.i('[AIProviderRegistry] ✅ Successfully loaded: $providerId');
          } else {
            Log.w('[AIProviderRegistry] ⚠️ Failed to initialize: $providerId');
          }
        } on Exception catch (e) {
          Log.e(
            '[AIProviderRegistry] ❌ Error loading provider $providerId: $e',
          );
        }
      }

      Log.i(
        '[AIProviderRegistry] ✅ Initialization complete: $successCount/$totalCount providers loaded',
      );

      if (successCount == 0) {
        Log.w('[AIProviderRegistry] ⚠️ No providers loaded successfully!');
      }
    } on Exception catch (e) {
      Log.e('[AIProviderRegistry] ❌ Failed to initialize registry: $e');
      // Fallback to empty registry - app can still work with manual registration
    }
  }

  /// Register a new provider
  Future<bool> registerProvider(final IAIProvider provider) async {
    try {
      final success = await provider.initialize({});
      _providers[provider.providerId] = provider;
      _initialized[provider.providerId] = success;

      Log.i(
        '[AIProviderRegistry] Registered provider: ${provider.providerId} (healthy: $success)',
      );
      return success;
    } on Exception catch (e) {
      Log.e(
        '[AIProviderRegistry] Failed to register provider ${provider.providerId}: $e',
      );
      return false;
    }
  }

  /// Get a provider by ID
  IAIProvider? getProvider(final String providerId) {
    return _providers[providerId];
  }

  /// Get all available providers
  List<IAIProvider> getAllProviders() {
    return _providers.values.toList();
  }

  /// Get healthy providers only
  List<IAIProvider> getHealthyProviders() {
    return _providers.entries
        .where((final entry) => _initialized[entry.key] == true)
        .map((final entry) => entry.value)
        .toList();
  }

  /// Get providers that support a specific capability
  List<IAIProvider> getProvidersForCapability(final AICapability capability) {
    return getHealthyProviders()
        .where((final provider) => provider.supportsCapability(capability))
        .toList();
  }

  /// Get the best provider for a capability (first healthy provider)
  IAIProvider? getBestProviderForCapability(final AICapability capability) {
    final providers = getProvidersForCapability(capability);
    return providers.isNotEmpty ? providers.first : null;
  }

  /// Get provider by model name using dynamic mapping
  IAIProvider? getProviderForModel(final String modelId) {
    // First try dynamic prefix mapping
    final providerId = AIProviderConfigLoader.getProviderIdForModel(modelId);
    if (providerId != null) {
      final provider = getProvider(providerId);
      if (provider != null) {
        return provider;
      }
    }

    // Fallback: iterate through healthy providers to find one that supports the model
    for (final provider in getHealthyProviders()) {
      for (final capability in provider.supportedCapabilities) {
        if (provider.supportsModel(capability, modelId)) {
          return provider;
        }
      }
    }

    Log.w('[AIProviderRegistry] No provider found for model: $modelId');
    return null;
  }

  /// Refresh health status for all providers
  Future<void> refreshHealth() async {
    for (final entry in _providers.entries) {
      try {
        _initialized[entry.key] = await entry.value.isHealthy();
      } on Exception catch (e) {
        Log.w('[AIProviderRegistry] Health check failed for ${entry.key}: $e');
        _initialized[entry.key] = false;
      }
    }
  }

  /// Dispose all providers
  Future<void> dispose() async {
    for (final provider in _providers.values) {
      try {
        await provider.dispose();
      } on Exception catch (e) {
        Log.w(
          '[AIProviderRegistry] Failed to dispose provider ${provider.providerId}: $e',
        );
      }
    }
    _providers.clear();
    _initialized.clear();
  }

  /// Get registry statistics
  Map<String, dynamic> getStats() {
    final healthy = _initialized.values.where((final h) => h).length;
    final total = _providers.length;

    return {
      'total_providers': total,
      'healthy_providers': healthy,
      'providers': _providers.keys.toList(),
      'health_status': Map.from(_initialized),
    };
  }
}
