/// Main orchestrator service for the Dynamic AI Providers system.
/// This service manages provider loading, fallback chains, smart routing,
/// and provides a unified interface for AI operations.
library;

import 'dart:async';
import 'package:ai_chan/shared/ai_providers/core/interfaces/i_ai_provider.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_provider_config.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_config_loader.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_factory.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

/// Exception thrown when no suitable provider is available
class NoProviderAvailableException implements Exception {
  const NoProviderAvailableException(this.message);

  final String message;

  @override
  String toString() => 'NoProviderAvailableException: $message';
}

/// Main manager for the Dynamic AI Providers system
class AIProviderManager {

  AIProviderManager._();
  static AIProviderManager? _instance;
  static AIProviderManager get instance => _instance ??= AIProviderManager._();

  AIProvidersConfig? _config;
  Map<String, IAIProvider> _providers = {};
  bool _initialized = false;

  /// Initialize the provider manager with configuration
  Future<bool> initialize({final String? configPath, final String? environment}) async {
    try {
      Log.i('Initializing AI Provider Manager');

      // Load configuration
      _config = configPath != null
          ? await AIProviderConfigLoader.loadFromFile(configPath)
          : await AIProviderConfigLoader.loadDefault();

      // Apply environment overrides if specified
      if (environment != null) {
        _config = AIProviderConfigLoader.applyEnvironmentOverrides(
          _config!,
          environment,
        );
      }

      // Validate environment variables
      final missingEnvVars =
          AIProviderConfigLoader.validateEnvironmentVariables(_config!);
      if (missingEnvVars.isNotEmpty) {
        Log.w('Missing environment variables: ${missingEnvVars.join(', ')}');
        // Continue initialization but some providers might fail
      }

      // Create providers from configuration
      _providers = AIProviderFactory.createProviders(_config!.aiProviders);

      // Initialize all providers
      final initResults = await _initializeProviders();

      // Log initialization results
      final successCount = initResults.values
          .where((final success) => success)
          .length;
      Log.i(
        'Initialized $successCount/${initResults.length} providers successfully',
      );

      // Validate fallback chains
      final chainErrors = AIProviderFactory.validateFallbackChains(
        _config!.aiProviders,
        _config!.fallbackChains,
      );

      if (chainErrors.isNotEmpty) {
        Log.w('Fallback chain validation warnings: ${chainErrors.join(', ')}');
      }

      _initialized = true;
      Log.i('AI Provider Manager initialized successfully');
      return true;
    } catch (e) {
      Log.e('Failed to initialize AI Provider Manager: $e');
      _initialized = false;
      return false;
    }
  }

  /// Send a message using the best available provider for the capability
  Future<AIResponse> sendMessage({
    required final List<Map<String, String>> history,
    required final SystemPrompt systemPrompt,
    required final AICapability capability,
    final String? preferredProviderId,
    final String? preferredModel,
    final String? imageBase64,
    final String? imageMimeType,
    final Map<String, dynamic>? additionalParams,
  }) async {
    if (!_initialized || _config == null) {
      throw StateError('AIProviderManager not initialized');
    }

    final providersToTry = _getProvidersForCapability(
      capability,
      preferredProviderId,
    );

    if (providersToTry.isEmpty) {
      throw NoProviderAvailableException(
        'No providers available for capability: ${capability.name}',
      );
    }

    Log.d(
      'Trying ${providersToTry.length} providers for ${capability.name}: ${providersToTry.join(', ')}',
    );

    Exception? lastException;

    for (final providerId in providersToTry) {
      final provider = _providers[providerId];
      if (provider == null) {
        Log.w('Provider $providerId not available, skipping');
        continue;
      }

      try {
        // Determine model to use
        final modelToUse = _selectModel(providerId, capability, preferredModel);

        Log.d(
          'Attempting request with provider: $providerId, model: $modelToUse',
        );

        final response = await provider.sendMessage(
          history: history,
          systemPrompt: systemPrompt,
          capability: capability,
          model: modelToUse,
          imageBase64: imageBase64,
          imageMimeType: imageMimeType,
          additionalParams: additionalParams,
        );

        Log.i('Successfully received response from provider: $providerId');
        return response;
      } catch (e) {
        Log.w('Provider $providerId failed: $e');
        lastException = e is Exception ? e : Exception(e.toString());

        // Continue to next provider in fallback chain
        continue;
      }
    }

    // All providers failed
    throw NoProviderAvailableException(
      'All providers failed for capability ${capability.name}. Last error: $lastException',
    );
  }

  /// Get available models for a specific capability
  Future<List<String>> getAvailableModels(
    final AICapability capability, {
    final String? providerId,
  }) async {
    if (!_initialized || _config == null) {
      throw StateError('AIProviderManager not initialized');
    }

    if (providerId != null) {
      final provider = _providers[providerId];
      if (provider != null && provider.supportsCapability(capability)) {
        return await provider.getAvailableModelsForCapability(capability);
      }
      return [];
    }

    // Get models from all providers that support the capability
    final allModels = <String>[];
    for (final entry in _providers.entries) {
      final provider = entry.value;
      if (provider.supportsCapability(capability)) {
        try {
          final models = await provider.getAvailableModelsForCapability(
            capability,
          );
          allModels.addAll(models);
        } catch (e) {
          Log.w('Failed to get models from provider ${entry.key}: $e');
        }
      }
    }

    return allModels.toSet().toList(); // Remove duplicates
  }

  /// Get all available providers
  Map<String, IAIProvider> get providers => Map.unmodifiable(_providers);

  /// Get configuration
  AIProvidersConfig? get config => _config;

  /// Check if manager is initialized
  bool get isInitialized => _initialized;

  /// Get providers that support a specific capability
  List<String> getProvidersByCapability(final AICapability capability) {
    if (!_initialized) return [];

    return _providers.entries
        .where((final entry) => entry.value.supportsCapability(capability))
        .map((final entry) => entry.key)
        .toList();
  }

  /// Health check for all providers
  Future<Map<String, bool>> healthCheck() async {
    if (!_initialized) return {};

    final results = <String, bool>{};

    for (final entry in _providers.entries) {
      try {
        results[entry.key] = await entry.value.isHealthy();
      } catch (e) {
        Log.w('Health check failed for provider ${entry.key}: $e');
        results[entry.key] = false;
      }
    }

    return results;
  }

  /// Reload configuration and reinitialize
  Future<bool> reload({final String? configPath, final String? environment}) async {
    Log.i('Reloading AI Provider Manager');

    // Dispose current providers
    await dispose();

    // Reinitialize
    return await initialize(configPath: configPath, environment: environment);
  }

  /// Dispose resources
  Future<void> dispose() async {
    Log.i('Disposing AI Provider Manager');

    for (final provider in _providers.values) {
      try {
        await provider.dispose();
      } catch (e) {
        Log.w('Error disposing provider: $e');
      }
    }

    _providers.clear();
    _config = null;
    _initialized = false;
    AIProviderFactory.clearCache();
  }

  /// Initialize all providers
  Future<Map<String, bool>> _initializeProviders() async {
    final results = <String, bool>{};

    for (final entry in _providers.entries) {
      final providerId = entry.key;
      final provider = entry.value;

      try {
        Log.d('Initializing provider: $providerId');
        final success = await provider.initialize({});
        results[providerId] = success;

        if (success) {
          Log.d('Provider $providerId initialized successfully');
        } else {
          Log.w('Provider $providerId failed to initialize');
        }
      } catch (e) {
        Log.e('Error initializing provider $providerId: $e');
        results[providerId] = false;
      }
    }

    return results;
  }

  /// Get ordered list of providers to try for a capability
  List<String> _getProvidersForCapability(
    final AICapability capability,
    final String? preferredProviderId,
  ) {
    final providers = <String>[];

    // Add preferred provider first if specified and available
    if (preferredProviderId != null &&
        _providers.containsKey(preferredProviderId) &&
        _providers[preferredProviderId]!.supportsCapability(capability)) {
      providers.add(preferredProviderId);
    }

    // Add providers from fallback chain
    if (_config!.fallbackChains.containsKey(capability)) {
      final chain = _config!.fallbackChains[capability]!;

      // Add primary provider if not already added
      if (!providers.contains(chain.primary) &&
          _providers.containsKey(chain.primary) &&
          _providers[chain.primary]!.supportsCapability(capability)) {
        providers.add(chain.primary);
      }

      // Add fallback providers
      for (final fallbackId in chain.fallbacks) {
        if (!providers.contains(fallbackId) &&
            _providers.containsKey(fallbackId) &&
            _providers[fallbackId]!.supportsCapability(capability)) {
          providers.add(fallbackId);
        }
      }
    } else {
      // No fallback chain defined, add all available providers sorted by priority
      final availableProviders = _providers.entries
          .where(
            (final entry) =>
                !providers.contains(entry.key) &&
                entry.value.supportsCapability(capability),
          )
          .toList();

      // Sort by priority (lower number = higher priority)
      availableProviders.sort((final a, final b) {
        final priorityA = _config!.aiProviders[a.key]?.priority ?? 999;
        final priorityB = _config!.aiProviders[b.key]?.priority ?? 999;
        return priorityA.compareTo(priorityB);
      });

      providers.addAll(availableProviders.map((final entry) => entry.key));
    }

    return providers;
  }

  /// Select the best model for a provider and capability
  String? _selectModel(
    final String providerId,
    final AICapability capability,
    final String? preferredModel,
  ) {
    final providerConfig = _config!.aiProviders[providerId];
    if (providerConfig == null) return null;

    // Use preferred model if specified and available
    if (preferredModel != null) {
      final availableModels = providerConfig.models[capability] ?? [];
      if (availableModels.contains(preferredModel)) {
        return preferredModel;
      }
    }

    // Use default model for the capability
    if (providerConfig.defaults.containsKey(capability)) {
      return providerConfig.defaults[capability];
    }

    // Use first available model as fallback
    final availableModels = providerConfig.models[capability];
    if (availableModels != null && availableModels.isNotEmpty) {
      return availableModels.first;
    }

    return null;
  }
}
