/// Multi-Model Routing Service for automatic provider switching based on capabilities.
/// Handles intelligent routing of requests to the best provider for each specific capability.
library;

import 'package:ai_chan/shared.dart';
// Consolidated import

/// Result of a routing decision
class RoutingResult {
  const RoutingResult({
    required this.provider,
    required this.modelId,
    required this.capability,
    this.wasAutoSwitched = false,
    this.originalProvider,
    this.reason,
  });

  final IAIProvider provider;
  final String modelId;
  final AICapability capability;
  final bool wasAutoSwitched;
  final String? originalProvider;
  final String? reason;

  @override
  String toString() =>
      'RoutingResult(provider: ${provider.providerId}, model: $modelId, autoSwitched: $wasAutoSwitched)';
}

/// Intelligent multi-model routing service
class MultiModelRouter {
  static final AIProviderRegistry _registry = AIProviderRegistry();

  /// Route a request to the best provider for the given capability and model
  static Future<RoutingResult?> route({
    required final AICapability capability,
    final String? preferredModel,
    final String? preferredProvider,
    final Map<String, dynamic>? additionalParams,
  }) async {
    Log.d(
      '[MultiModelRouter] 🎯 Routing request: capability=$capability, model=$preferredModel, provider=$preferredProvider',
    );

    try {
      // Step 1: If specific model is requested, try to detect provider from model name
      if (preferredModel != null) {
        final detectedProvider = _getProviderForModel(preferredModel);
        if (detectedProvider != null) {
          if (detectedProvider.supportsCapability(capability)) {
            Log.i(
              '[MultiModelRouter] ✅ Using model-specific provider: ${detectedProvider.providerId} for $preferredModel',
            );
            return RoutingResult(
              provider: detectedProvider,
              modelId: preferredModel,
              capability: capability,
            );
          } else {
            // Model-specific provider doesn't support this capability - need to auto-switch
            final fallbackResult = await _findFallbackProvider(
              capability,
              preferredModel,
              detectedProvider.providerId,
            );
            if (fallbackResult != null) {
              Log.w(
                '[MultiModelRouter] 🔀 AUTO-SWITCH: ${detectedProvider.providerId} doesn\'t support $capability, switching to ${fallbackResult.provider.providerId}',
              );
              return fallbackResult;
            }
          }
        }
      }

      // Step 2: If specific provider is requested, try to use it
      if (preferredProvider != null) {
        final provider = _registry.getProvider(preferredProvider);
        if (provider != null && provider.supportsCapability(capability)) {
          final modelId =
              preferredModel ??
              _getBestModelForCapability(provider, capability);
          if (modelId != null) {
            Log.i(
              '[MultiModelRouter] ✅ Using preferred provider: $preferredProvider for $capability',
            );
            return RoutingResult(
              provider: provider,
              modelId: modelId,
              capability: capability,
            );
          }
        } else {
          // Preferred provider doesn't support capability - auto-switch
          final fallbackResult = await _findFallbackProvider(
            capability,
            preferredModel,
            preferredProvider,
          );
          if (fallbackResult != null) {
            Log.w(
              '[MultiModelRouter] 🔀 AUTO-SWITCH: $preferredProvider doesn\'t support $capability, switching to ${fallbackResult.provider.providerId}',
            );
            return fallbackResult;
          }
        }
      }

      // Step 3: Find best provider for capability automatically
      final bestProvider = _registry.getBestProviderForCapability(capability);
      if (bestProvider != null) {
        final modelId =
            preferredModel ??
            _getBestModelForCapability(bestProvider, capability);
        if (modelId != null) {
          Log.i(
            '[MultiModelRouter] ✅ Auto-selected best provider: ${bestProvider.providerId} for $capability',
          );
          return RoutingResult(
            provider: bestProvider,
            modelId: modelId,
            capability: capability,
          );
        }
      }

      Log.e(
        '[MultiModelRouter] ❌ No suitable provider found for capability: $capability',
      );
      return null;
    } on Exception catch (e) {
      Log.e('[MultiModelRouter] ❌ Routing failed: $e');
      return null;
    }
  }

  /// Get provider for a specific model using registered prefixes
  static IAIProvider? _getProviderForModel(final String modelId) {
    final providerId = getProviderIdForModel(modelId);
    if (providerId != null) {
      return _registry.getProvider(providerId);
    }
    return null;
  }

  /// Find a fallback provider when the preferred one doesn't support the capability
  static Future<RoutingResult?> _findFallbackProvider(
    final AICapability capability,
    final String? originalModel,
    final String originalProviderId,
  ) async {
    final fallbackProviders = _registry.getProvidersForCapability(capability);

    for (final provider in fallbackProviders) {
      if (provider.providerId != originalProviderId) {
        final modelId =
            originalModel ?? _getBestModelForCapability(provider, capability);
        if (modelId != null) {
          return RoutingResult(
            provider: provider,
            modelId: modelId,
            capability: capability,
            wasAutoSwitched: true,
            originalProvider: originalProviderId,
            reason: 'Original provider doesn\'t support $capability',
          );
        }
      }
    }

    return null;
  }

  /// Get the best model for a capability from a specific provider
  static String? _getBestModelForCapability(
    final IAIProvider provider,
    final AICapability capability,
  ) {
    // Obtener modelos desde metadatos del provider
    final metadata = provider.metadata;
    final capabilityModels = metadata.availableModels[capability];
    if (capabilityModels != null && capabilityModels.isNotEmpty) {
      return capabilityModels.first;
    }

    // Último fallback: null si no hay modelos disponibles
    return null;
  }
}
