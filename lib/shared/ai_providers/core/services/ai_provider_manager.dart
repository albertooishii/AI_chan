/// Main orchestrator service for the Dynamic AI Providers system.
/// This service manages provider loading, fallback chains, smart routing,
/// and provides a unified interface for AI operations.
library;

import 'dart:async';
import 'dart:io';
import 'package:ai_chan/shared/ai_providers/core/interfaces/i_ai_provider.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_provider_config.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_config_loader.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_factory.dart';
import 'package:ai_chan/shared/ai_providers/core/interfaces/i_cache_service.dart';
import 'package:ai_chan/shared/ai_providers/core/services/in_memory_cache_service.dart';
import 'package:ai_chan/shared/ai_providers/core/services/performance_monitoring_service.dart';
import 'package:ai_chan/shared/ai_providers/core/services/request_deduplication_service.dart';
import 'package:ai_chan/shared/ai_providers/core/interfaces/i_http_connection_pool.dart';
import 'package:ai_chan/shared/ai_providers/core/services/http_connection_pool.dart';
import 'package:ai_chan/shared/ai_providers/core/interfaces/i_retry_service.dart';
import 'package:ai_chan/shared/ai_providers/core/services/intelligent_retry_service.dart';
import 'package:ai_chan/shared/ai_providers/core/interfaces/i_alert_service.dart';
import 'package:ai_chan/shared/ai_providers/core/services/provider_alert_service.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';
import 'package:ai_chan/shared/ai_providers/core/services/image_persistence_service.dart';

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
  static bool _autoInitializeCalled = false;

  static AIProviderManager get instance {
    if (!_autoInitializeCalled) {
      _autoInitializeCalled = true;
      // Schedule auto-initialization on first access
      Future.microtask(() => _instance.initialize());
    }
    return _instance;
  }

  AIProvidersConfig? _config;
  final Map<String, IAIProvider> _providers = {};
  bool _initialized = false;

  // Performance and optimization services
  ICacheService? _cacheService;
  PerformanceMonitoringService? _performanceService;
  RequestDeduplicationService? _deduplicationService;

  // Advanced Phase 6 services
  IHttpConnectionPool? _connectionPool;
  IRetryService? _retryService;
  IProviderAlertService? _alertService;

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
      final providers = await AIProviderFactory.createProviders(
        _config!.aiProviders,
      );
      _providers.clear();
      _providers.addAll(providers);

      // Initialize optimization services (cache, monitoring, deduplication)
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

      // Initialize advanced Phase 6 services
      _initializeAdvancedServices();
    } on Exception catch (e) {
      Log.w('Failed to initialize optimization services: $e');
      // Continue without optimization services
    }
  }

  /// Initialize advanced Phase 6 services
  void _initializeAdvancedServices() {
    try {
      // Initialize HTTP connection pool
      _connectionPool = HttpConnectionPool();
      _connectionPool!.initialize(const ConnectionPoolConfig());
      Log.d('HTTP connection pool initialized');

      // Initialize intelligent retry service
      _retryService = IntelligentRetryService();
      _retryService!.initialize(
        const RetryConfig(),
        const CircuitBreakerConfig(),
      );
      Log.d('Intelligent retry service initialized');

      // Initialize provider alert service
      _alertService = ProviderAlertService();
      _alertService!.initialize(const AlertThresholds());
      Log.d('Provider alert service initialized');

      Log.i('Advanced Phase 6 services initialized successfully');
    } on Exception catch (e) {
      Log.w('Failed to initialize advanced services: $e');
      // Continue without advanced services
    }
  }

  /// Ensure the manager is initialized, waiting if necessary
  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    // If already initializing, wait for it
    int attempts = 0;
    while (!_initialized && attempts < 50) {
      // Max 5 seconds wait
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    // If still not initialized, try to initialize
    if (!_initialized) {
      await initialize();
    }
  }

  /// Send a message using the best available provider for the capability
  /// Automatically selects the optimal provider and model based on capability and user preferences
  Future<AIResponse> sendMessage({
    required final List<Map<String, String>> history,
    required final SystemPrompt systemPrompt,
    final AICapability capability =
        AICapability.textGeneration, // Default to text generation
    final String? imageBase64,
    final String? imageMimeType,
    final Map<String, dynamic>? additionalParams,
  }) async {
    // Wait for initialization if needed
    if (!_initialized) {
      await _ensureInitialized();
    }

    if (!_initialized || _config == null) {
      throw StateError('AIProviderManager failed to initialize');
    }

    // Ignore deprecated parameters and use automatic selection
    // preferredProviderId and preferredModel are deprecated - we calculate optimal selection here

    // If the user has selected a specific model in preferences, prefer the
    // provider that supports that model for this capability. This ensures
    // explicit user selection (e.g. "gpt-4.1-mini") is respected instead
    // of always using the fallback chain primary provider (e.g. Google).
    String? preferredProviderId;
    try {
      final selectedModel = await _getSavedModelForCapability(capability);
      if (selectedModel != null) {
        final modelProvider = await getProviderForModel(
          selectedModel,
          capability,
        );
        if (modelProvider != null) {
          preferredProviderId = modelProvider.providerId;
          Log.d(
            '[AIProviderManager] Preferring provider $preferredProviderId for user-selected model: $selectedModel',
          );
        } else {
          Log.d(
            '[AIProviderManager] User-selected model not supported by any provider for capability ${capability.name}: $selectedModel',
          );
        }
      }
    } on Exception catch (e) {
      Log.w('[AIProviderManager] Failed to read selected model from prefs: $e');
    }

    // Calculate the actual provider and model that will be used for fingerprinting
    final providersToTry = _getProvidersForCapability(
      capability,
      preferredProviderId,
    );
    String actualProviderId = '';
    String actualModel = '';

    if (providersToTry.isNotEmpty) {
      actualProviderId =
          providersToTry.first; // Use the first provider that would be tried
      actualModel =
          await _getModelForCapability(capability, actualProviderId) ?? '';
    }

    // Try deduplication service if available
    if (_deduplicationService != null) {
      final fingerprint = _deduplicationService!.createFingerprint(
        providerId: actualProviderId, // Use calculated provider
        model: actualModel, // Use calculated model
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
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      additionalParams: additionalParams,
    );
  }

  /// Internal method to send message with performance monitoring and caching
  /// Uses automatic provider and model selection - no manual preferences
  Future<AIResponse> _sendMessageWithMonitoring({
    required final List<Map<String, String>> history,
    required final SystemPrompt systemPrompt,
    required final AICapability capability,
    final String? imageBase64,
    final String? imageMimeType,
    final Map<String, dynamic>? additionalParams,
  }) async {
    // Attempt to respect user-selected model/provider where possible.
    String? preferredProviderId;
    String? savedModel;
    try {
      savedModel = await _getSavedModelForCapability(capability);
      if (savedModel != null) {
        final modelProvider = await getProviderForModel(savedModel, capability);
        if (modelProvider != null) {
          preferredProviderId = modelProvider.providerId;
          Log.d(
            '[AIProviderManager] _sendMessage: user-selected model "$savedModel" maps to provider $preferredProviderId',
          );
        } else {
          Log.d(
            '[AIProviderManager] _sendMessage: user-selected model "$savedModel" not supported by any provider for capability ${capability.name}',
          );
        }
      }
    } on Exception catch (e) {
      Log.w(
        '[AIProviderManager] _sendMessage: failed reading selected model from prefs: $e',
      );
    }

    // Use the preferred provider id (if found) so the provider order respects user selection
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
        // Calculate the model that will actually be used for proper cache key
        String? modelToUseForCache = await _getSavedModelForProviderIfSupported(
          capability,
          providerId,
        );
        modelToUseForCache ??= await _getModelForCapability(
          capability,
          providerId,
        );

        cacheKey = CacheKey(
          providerId: providerId,
          model:
              modelToUseForCache ??
              '', // Use actual model that will be selected
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
        // Use intelligent model selection based on capability and user preferences
        String? modelToUse;
        try {
          modelToUse = await _getSavedModelForProviderIfSupported(
            capability,
            providerId,
          );
        } on Exception catch (_) {
          // ignore and fallback to auto selection below
        }

        modelToUse ??= await _getModelForCapability(capability, providerId);

        Log.d(
          'Attempting request with provider: $providerId, model: $modelToUse (intelligent selection)',
        );

        // Build a guarded operation so retries will re-execute both the provider
        // call and the image-presence check. This ensures the centralized retry
        // service can detect and retry an empty-image result.
        final requestedImage =
            additionalParams?['enableImageGeneration'] == true ||
            capability == AICapability.imageGeneration;

        Future<AIResponse> guardedCallOperation() async {
          final resp = await provider.sendMessage(
            history: history,
            systemPrompt: systemPrompt,
            capability: capability,
            model: modelToUse,
            imageBase64: imageBase64,
            imageMimeType: imageMimeType,
            additionalParams: additionalParams,
          );

          if (requestedImage && resp.base64.isEmpty) {
            Log.w(
              '[AIProviderManager] Provider $providerId returned no image despite imageGeneration requested. Forcing retry fallback.',
            );
            throw HttpException('520 Empty image result from $providerId');
          }

          return resp;
        }

        AIResponse response = _retryService != null
            ? await _retryService!.executeWithRetry<AIResponse>(
                guardedCallOperation,
                providerId,
              )
            : await guardedCallOperation();

        // If provider returned an image as base64, persist it centrally and
        // replace base64 in the returned AIResponse with an empty string while
        // populating `imageFileName` so callers can use that name.
        try {
          if (response.base64.isNotEmpty) {
            final saved = await ImagePersistenceService.instance
                .saveBase64Image(response.base64);
            if (saved != null && saved.isNotEmpty) {
              // Create a new AIResponse with cleared base64 and imageFileName set
              response = AIResponse(
                text: response.text,
                seed: response.seed,
                prompt: response.prompt,
                imageFileName: saved,
              );
            } else {
              Log.w(
                '[AIProviderManager] Failed to persist returned base64 image for provider $providerId',
              );
            }
          }
        } on Exception catch (e) {
          Log.w(
            '[AIProviderManager] Error persisting returned base64 image: $e',
          );
        }

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

        Log.i(
          'Successfully received response from provider: $providerId (intelligent selection)',
        );
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
    // Wait for initialization if needed
    if (!_initialized) {
      await _ensureInitialized();
    }

    if (!_initialized || _config == null) {
      throw StateError('AIProviderManager failed to initialize');
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

  /// Get the appropriate provider for a specific model
  Future<IAIProvider?> getProviderForModel(
    final String modelId,
    final AICapability capability,
  ) async {
    if (!_initialized) return null;

    final modelLower = modelId.toLowerCase().trim();

    // Model-based provider selection
    for (final entry in _providers.entries) {
      final provider = entry.value;
      final providerId = entry.key;

      // Skip if provider doesn't support the capability
      if (!provider.supportsCapability(capability)) {
        continue;
      }

      // Check if this provider supports this model
      final availableModels = await provider.getAvailableModelsForCapability(
        capability,
      );
      final supportsModel = availableModels.any(
        (final String model) => model.toLowerCase().trim() == modelLower,
      );

      if (supportsModel && await provider.isHealthy()) {
        Log.i('Selected provider $providerId for model: $modelId');
        return provider;
      }

      // Provider-specific model pattern matching as fallback
      if (await provider.isHealthy()) {
        // 🚀 DINÁMICO: Solo usar como fallback si ningún proveedor soportó exactamente el modelo
        // No hardcodear patrones específicos de modelos por proveedor
        Log.i('Using $providerId as fallback provider for model: $modelId');
      }
    }

    Log.w('No provider found for model: $modelId with capability: $capability');
    return null;
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

  /// Read the saved selected model from preferences (single place)
  Future<String?> _getSavedModelForCapability(
    final AICapability capability,
  ) async {
    try {
      final savedModel = await PrefsUtils.getSelectedModel();
      if (savedModel != null && savedModel.trim().isNotEmpty) {
        return savedModel.trim();
      }
      return null;
    } on Exception catch (e) {
      Log.w(
        '[AIProviderManager] _getSavedModelForCapability: failed to read prefs: $e',
      );
      return null;
    }
  }

  /// If user has a saved model and the given provider supports it for the capability,
  /// return that saved model, otherwise null.
  Future<String?> _getSavedModelForProviderIfSupported(
    final AICapability capability,
    final String providerId,
  ) async {
    final savedModel = await _getSavedModelForCapability(capability);
    if (savedModel == null) return null;

    final providerConfig = _config!.aiProviders[providerId];
    final availableModels = providerConfig?.models[capability] ?? [];
    if (availableModels.contains(savedModel)) {
      return savedModel;
    }

    return null;
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

  /// Get default model for a capability from the best available provider (DYNAMIC)
  /// Reemplaza Config.getDefaultTextModel() y métodos similares hardcodeados
  Future<String?> getDefaultModelForCapability(
    final AICapability capability,
  ) async {
    try {
      final provider = await getProviderForCapability(capability);
      if (provider == null) {
        Log.w(
          '[AIProviderManager] No provider available for capability: ${capability.identifier}',
        );
        return null;
      }

      final model = _selectModel(provider.providerId, capability, null);
      if (model != null) {
        Log.d(
          '[AIProviderManager] ✅ Default model for ${capability.identifier}: $model (provider: ${provider.providerId})',
        );
        return model;
      }

      Log.w(
        '[AIProviderManager] No default model found for capability: ${capability.identifier}',
      );
      return null;
    } on Exception catch (e) {
      Log.e(
        '[AIProviderManager] Error getting default model for ${capability.identifier}: $e',
      );
      return null;
    }
  }

  /// Get default text generation model (replacement for Config.getDefaultTextModel)
  Future<String?> getDefaultTextModel() async {
    return getDefaultModelForCapability(AICapability.textGeneration);
  }

  /// Get default image generation model (replacement for Config.getDefaultImageModel)
  Future<String?> getDefaultImageModel() async {
    return getDefaultModelForCapability(AICapability.imageGeneration);
  }

  /// Get default image analysis model
  Future<String?> getDefaultImageAnalysisModel() async {
    return getDefaultModelForCapability(AICapability.imageAnalysis);
  }

  /// Get default audio generation model
  Future<String?> getDefaultAudioModel() async {
    return getDefaultModelForCapability(AICapability.audioGeneration);
  }

  /// Get default realtime conversation model
  Future<String?> getDefaultRealtimeModel() async {
    return getDefaultModelForCapability(AICapability.realtimeConversation);
  }

  /// Get the appropriate model based on capability and user preferences
  /// Handles manual selection for text/audio and auto-selection for other capabilities
  Future<String?> _getModelForCapability(
    final AICapability capability,
    final String providerId,
  ) async {
    switch (capability) {
      case AICapability.textGeneration:
        // For text: use manual selection from SharedPreferences or fallback to auto
        try {
          final savedModel = await PrefsUtils.getSelectedModel();
          if (savedModel != null && savedModel.trim().isNotEmpty) {
            // Verify the saved model is available for this provider
            final providerConfig = _config!.aiProviders[providerId];
            final availableModels = providerConfig?.models[capability] ?? [];
            if (availableModels.contains(savedModel)) {
              return savedModel;
            }
          }
        } on Exception catch (e) {
          Log.w('Failed to get saved text model: $e');
        }
        // Fallback to auto-selection
        return _selectModel(providerId, capability, null);

      case AICapability.audioGeneration:
      case AICapability.realtimeConversation:
        // For audio/voice: could implement voice preference logic here
        // For now, use auto-selection but this could be extended
        return _selectModel(providerId, capability, null);

      default:
        // For images and other capabilities: always auto-selection
        return _selectModel(providerId, capability, null);
    }
  }
}
