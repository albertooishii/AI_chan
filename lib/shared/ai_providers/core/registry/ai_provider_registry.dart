import 'package:ai_chan/shared/ai_providers/core/interfaces/i_ai_provider.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/shared/ai_providers/implementations/google_provider.dart';
import 'package:ai_chan/shared/ai_providers/implementations/xai_provider.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Central registry for all AI providers in the dynamic provider system.
///
/// This registry maintains compatibility with the existing runtime factory
/// system while providing the new plugin architecture interface.
class AIProviderRegistry {
  AIProviderRegistry._internal();
  factory AIProviderRegistry() => _instance;
  static final AIProviderRegistry _instance = AIProviderRegistry._internal();

  final Map<String, IAIProvider> _providers = {};
  final Map<String, bool> _initialized = {};

  /// Initialize the registry with default providers
  Future<void> initialize() async {
    await registerProvider(GoogleProvider());
    await registerProvider(XAIProvider());

    Log.i(
      '[AIProviderRegistry] Initialized with ${_providers.length} providers',
    );
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

  /// Get provider by model name (maintains compatibility with existing system)
  IAIProvider? getProviderForModel(final String modelId) {
    final normalized = modelId.trim().toLowerCase();

    // Map model prefixes to providers (preserving existing logic)
    if (normalized.startsWith('gpt-') ||
        normalized.startsWith('dall-e') ||
        normalized.startsWith('gpt-realtime')) {
      return getProvider('openai');
    }

    if (normalized.startsWith('gemini-') || normalized.startsWith('imagen-')) {
      return getProvider('google');
    }

    if (normalized.startsWith('grok-')) {
      return getProvider('xai');
    }

    // Fallback: try to find any provider that supports the model
    for (final provider in getHealthyProviders()) {
      for (final capability in provider.supportedCapabilities) {
        if (provider.supportsModel(capability, modelId)) {
          return provider;
        }
      }
    }

    return null;
  }

  /// Check if a provider is healthy
  bool isProviderHealthy(final String providerId) {
    return _initialized[providerId] == true;
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
