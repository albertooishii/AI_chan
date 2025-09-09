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
import 'package:ai_chan/shared/ai_providers/core/interfaces/i_cache_service.dart';
import 'package:ai_chan/shared/ai_providers/core/services/in_memory_cache_service.dart';
import 'package:ai_chan/shared/ai_providers/core/services/performance_monitoring_service.dart';
import 'package:ai_chan/shared/ai_providers/core/services/request_deduplication_service.dart';
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
  AIProviderManager._internal();
  static final AIProviderManager _instance = AIProviderManager._internal();
  static AIProviderManager get instance => _instance;

  AIProvidersConfig? _config;
  final Map<String, IAIProvider> _providers = {};
  bool _initialized = false;

  // Performance and optimization services
  ICacheService? _cacheService;
  PerformanceMonitoringService? _performanceService;
  RequestDeduplicationService? _deduplicationService;

  /// Initialize the manager with configuration
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      Log.i('Initializing AI Provider Manager...');

      // Load configuration
      _config = await AIProviderConfigLoader.loadDefault();
      Log.d(
        'Loaded configuration: ${_config!.aiProviders.length} providers defined',
      );

      // Create providers
      final providers = AIProviderFactory.createProviders(_config!.aiProviders);
      _providers.clear();
      _providers.addAll(providers);

      // Initialize performance and optimization services
      _initializeOptimizationServices();

      _initialized = true;
      Log.i('AI Provider Manager initialized successfully');
    } on Exception catch (e) {
      Log.e('Failed to initialize AI Provider Manager', error: e);
      rethrow;
    }
  }

  /// Initialize optimization services (cache, monitoring, deduplication)
  void _initializeOptimizationServices() {
    try {
      // Initialize cache service
      _cacheService = InMemoryCacheService();
      Log.d('Cache service initialized');

      // Initialize performance monitoring
      _performanceService = PerformanceMonitoringService();
      Log.d('Performance monitoring service initialized');

      // Initialize request deduplication
      _deduplicationService = RequestDeduplicationService();
      Log.d('Request deduplication service initialized');
    } on Exception catch (e) {
      Log.w('Failed to initialize optimization services: $e');
      // Continue without optimization services
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

    // Try deduplication service if available
    if (_deduplicationService != null) {
      final fingerprint = _deduplicationService!.createFingerprint(
        providerId: preferredProviderId ?? '',
        model: preferredModel ?? '',
        capability: capability.name,
        history: history,
        systemPrompt: systemPrompt,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
        additionalParams: additionalParams,
      );

      return _deduplicationService!.getOrCreateRequest(
        fingerprint,
        () => _sendMessageWithMonitoring(
          history: history,
          systemPrompt: systemPrompt,
          capability: capability,
          preferredProviderId: preferredProviderId,
          preferredModel: preferredModel,
          imageBase64: imageBase64,
          imageMimeType: imageMimeType,
          additionalParams: additionalParams,
        ),
      );
    }

    // Fallback to direct execution if deduplication is not available
    return _sendMessageWithMonitoring(
      history: history,
      systemPrompt: systemPrompt,
      capability: capability,
      preferredProviderId: preferredProviderId,
      preferredModel: preferredModel,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      additionalParams: additionalParams,
    );
  }

  /// Internal method to send message with performance monitoring and caching
  Future<AIResponse> _sendMessageWithMonitoring({
    required final List<Map<String, String>> history,
    required final SystemPrompt systemPrompt,
    required final AICapability capability,
    final String? preferredProviderId,
    final String? preferredModel,
    final String? imageBase64,
    final String? imageMimeType,
    final Map<String, dynamic>? additionalParams,
  }) async {
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

      // Check cache first if available
      CacheKey? cacheKey;
      if (_cacheService != null) {
        cacheKey = CacheKey(
          providerId: providerId,
          model: preferredModel ?? '',
          capability: capability.name,
          messageHash: history.toString().hashCode.toString(),
          additionalData: additionalParams ?? {},
        );

        final cachedResponse = await _cacheService!.get(cacheKey);
        if (cachedResponse != null) {
          Log.d('Cache hit for provider: $providerId');
          return cachedResponse;
        }
      }

      // Start performance monitoring
      final startTime = _performanceService?.startTiming() ?? DateTime.now();

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

        // Record successful performance metrics
        _performanceService?.recordRequest(
          providerId: providerId,
          startTime: startTime,
          success: true,
        );

        // Cache the response if caching is available
        if (_cacheService != null && cacheKey != null) {
          await _cacheService!.set(cacheKey, response);
        }

        Log.i('Successfully received response from provider: $providerId');
        return response;
      } on Exception catch (e) {
        Log.w('Provider $providerId failed: $e');
        lastException = e;

        // Record failed performance metrics
        _performanceService?.recordRequest(
          providerId: providerId,
          startTime: startTime,
          success: false,
          errorType: e.runtimeType.toString(),
        );

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
        } on Exception catch (e) {
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

  /// Get the first available provider for a specific capability
  Future<IAIProvider?> getProviderForCapability(
    final AICapability capability,
  ) async {
    if (!_initialized) return null;

    final providersForCapability = _getProvidersForCapability(capability, null);

    for (final providerId in providersForCapability) {
      final provider = _providers[providerId];
      if (provider != null && await provider.isHealthy()) {
        return provider;
      }
    }

    return null;
  }

  /// Health check for all providers
  Future<Map<String, bool>> healthCheck() async {
    if (!_initialized) return {};

    final results = <String, bool>{};

    for (final entry in _providers.entries) {
      try {
        results[entry.key] = await entry.value.isHealthy();
      } on Exception catch (e) {
        Log.w('Health check failed for provider ${entry.key}: $e');
        results[entry.key] = false;
      }
    }

    return results;
  }

  /// Reload configuration and reinitialize
  Future<bool> reload({
    final String? configPath,
    final String? environment,
  }) async {
    Log.i('Reloading AI Provider Manager');

    // Dispose current providers
    await dispose();

    // Reinitialize
    await initialize();
    return true;
  }

  /// Dispose resources
  Future<void> dispose() async {
    Log.i('Disposing AI Provider Manager');

    for (final provider in _providers.values) {
      try {
        await provider.dispose();
      } on Exception catch (e) {
        Log.w('Error disposing provider: $e');
      }
    }

    // Dispose optimization services
    if (_cacheService is InMemoryCacheService) {
      (_cacheService as InMemoryCacheService).dispose();
    }

    _deduplicationService?.dispose();

    _providers.clear();
    _config = null;
    _initialized = false;
    AIProviderFactory.clearCache();
  }

  /// Get comprehensive system statistics including performance metrics
  Map<String, dynamic> getSystemStats() {
    final baseStats = {
      'initialized': _initialized,
      'total_providers': _providers.length,
      'available_providers': _providers.keys.toList(),
      'has_cache': _cacheService != null,
      'has_performance_monitoring': _performanceService != null,
      'has_deduplication': _deduplicationService != null,
    };

    // Add cache statistics if available
    if (_cacheService != null) {
      try {
        final cacheStats = _cacheService!.getStats();
        baseStats['cache_stats'] = cacheStats;
      } on Exception catch (e) {
        baseStats['cache_stats_error'] = e.toString();
      }
    }

    // Add performance statistics if available
    if (_performanceService != null) {
      try {
        final perfStats = _performanceService!.getSystemStats();
        baseStats['performance_stats'] = perfStats;
      } on Exception catch (e) {
        baseStats['performance_stats_error'] = e.toString();
      }
    }

    // Add deduplication statistics if available
    if (_deduplicationService != null) {
      try {
        final dedupStats = _deduplicationService!.getStats();
        baseStats['deduplication_stats'] = dedupStats;
      } on Exception catch (e) {
        baseStats['deduplication_stats_error'] = e.toString();
      }
    }

    return baseStats;
  }

  /// Get performance metrics for a specific provider
  ProviderMetrics? getProviderPerformanceMetrics(final String providerId) {
    return _performanceService?.getProviderMetrics(providerId);
  }

  /// Get provider health rankings based on performance
  List<MapEntry<String, double>> getProviderHealthRankings() {
    return _performanceService?.getProviderHealthScores() ?? [];
  }

  /// Clear all caches and reset performance metrics
  Future<void> clearOptimizationData() async {
    await _cacheService?.clear();
    _performanceService?.clearMetrics();
    _deduplicationService?.clearInFlightRequests();
    _deduplicationService?.resetStats();
    Log.i('Cleared all optimization data');
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
