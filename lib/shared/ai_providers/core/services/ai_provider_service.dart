import 'package:ai_chan/shared.dart';

/// High-level service that provides centralized access to AI providers.
///
/// This service is the main entry point for accessing AI providers with
/// dynamic configuration and capability-based selection.
class AIProviderService {
  factory AIProviderService() => _instance;
  AIProviderService._internal();
  static final AIProviderService _instance = AIProviderService._internal();

  late final AIProviderRegistry _registry;
  bool _initialized = false;

  /// Initialize the provider service
  Future<void> initialize() async {
    if (_initialized) return;

    _registry = AIProviderRegistry();
    await _registry.initialize();
    _initialized = true;

    Log.i('[AIProviderService] Initialized successfully');
  }

  /// Get provider for model
  IAIProvider? getProviderForModel(final String modelId) {
    _ensureInitialized();
    return _registry.getProviderForModel(modelId);
  }

  /// Get providers for capability
  List<IAIProvider> getProvidersForCapability(final AICapability capability) {
    _ensureInitialized();
    return _registry.getProvidersForCapability(capability);
  }

  /// Send message using the new provider system
  Future<AIResponse> sendMessage({
    required final String modelId,
    required final List<Map<String, String>> history,
    required final SystemPrompt systemPrompt,
    required final AICapability capability,
    final String? imageBase64,
    final String? imageMimeType,
    final Map<String, dynamic>? additionalParams,
  }) async {
    _ensureInitialized();

    // Try to use new provider system first
    final provider = getProviderForModel(modelId);
    if (provider != null && provider.supportsCapability(capability)) {
      try {
        Log.d(
          '[AIProviderService] Using new provider system: ${provider.providerId}',
        );
        final providerResp = await provider.sendMessage(
          history: history,
          systemPrompt: systemPrompt,
          capability: capability,
          model: modelId,
          imageBase64: imageBase64,
          imageMimeType: imageMimeType,
          additionalParams: additionalParams,
        );

        // Providers now return ProviderResponse; expose AIResponse to callers.
        // Build an AIResponse-like object from ProviderResponse fields so the
        // rest of the app (which still expects AIResponse) continues to work.
        return AIResponse(
          text: providerResp.text,
          seed: providerResp.seed,
          prompt: providerResp.prompt,
        );
      } on Exception catch (e) {
        Log.w('[AIProviderService] Provider failed: $e');
        // No fallback - throw the error
        rethrow;
      }
    }

    // No provider available for the requested model
    throw Exception('No provider available for model: $modelId');
  }

  /// Get available models for capability
  Future<List<String>> getAvailableModelsForCapability(
    final AICapability capability,
  ) async {
    _ensureInitialized();

    final providers = getProvidersForCapability(capability);
    final allModels = <String>[];

    for (final provider in providers) {
      try {
        final models = await provider.getAvailableModelsForCapability(
          capability,
        );
        allModels.addAll(models);
      } on Exception catch (e) {
        Log.w(
          '[AIProviderService] Failed to get models from ${provider.providerId}: $e',
        );
      }
    }

    return allModels.toSet().toList(); // Remove duplicates
  }

  /// Check if model is supported for capability
  bool supportsModelForCapability(
    final String modelId,
    final AICapability capability,
  ) {
    _ensureInitialized();

    final provider = getProviderForModel(modelId);
    return provider?.supportsModel(capability, modelId) == true;
  }

  /// Get best provider for capability
  IAIProvider? getBestProviderForCapability(final AICapability capability) {
    _ensureInitialized();
    return _registry.getBestProviderForCapability(capability);
  }

  /// Get default model for capability from best provider
  String? getDefaultModelForCapability(final AICapability capability) {
    _ensureInitialized();

    final provider = getBestProviderForCapability(capability);
    return provider?.getDefaultModel(capability);
  }

  /// Get all available providers
  List<IAIProvider> getAllProviders() {
    _ensureInitialized();
    return _registry.getAllProviders();
  }

  /// Get service statistics
  Map<String, dynamic> getStats() {
    _ensureInitialized();
    return _registry.getStats();
  }

  /// Refresh health status
  Future<void> refreshHealth() async {
    _ensureInitialized();
    await _registry.refreshHealth();
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'AIProviderService not initialized. Call initialize() first.',
      );
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    if (_initialized) {
      await _registry.dispose();
      _initialized = false;
    }
  }
}
