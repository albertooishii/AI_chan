/// Multi-Model Routing Service for automatic provider switching based on capabilities.
/// Handles intelligent routing of requests to the best provider for each specific capability.
library;

import 'package:ai_chan/shared/ai_providers/core/interfaces/i_ai_provider.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/shared/ai_providers/core/registry/ai_provider_registry.dart';
import 'package:ai_chan/shared/ai_providers/core/registry/provider_registration.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

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

  /// Special routing for image generation requests
  static Future<RoutingResult?> routeImageGeneration({
    final String? preferredModel,
    final String? preferredProvider,
    final Map<String, dynamic>? additionalParams,
  }) async {
    Log.d('[MultiModelRouter] 🎨 Routing image generation request');

    // Image generation typically requires specific providers
    // Check if current provider supports it, otherwise auto-switch to one that does

    final result = await route(
      capability: AICapability.imageGeneration,
      preferredModel:
          preferredModel ?? 'dall-e-3', // Default to DALL-E for images
      preferredProvider: preferredProvider,
      additionalParams: additionalParams,
    );

    if (result != null && result.wasAutoSwitched) {
      Log.i(
        '[MultiModelRouter] 🎨 AUTO-SWITCH for image generation: ${result.originalProvider} → ${result.provider.providerId}',
      );
    }

    return result;
  }

  /// Special routing for image analysis requests
  static Future<RoutingResult?> routeImageAnalysis({
    final String? preferredModel,
    final String? preferredProvider,
    final Map<String, dynamic>? additionalParams,
  }) async {
    Log.d('[MultiModelRouter] 👁️ Routing image analysis request');

    final result = await route(
      capability: AICapability.imageAnalysis,
      preferredModel:
          preferredModel ??
          'gpt-4-vision-preview', // Default to GPT-4V for analysis
      preferredProvider: preferredProvider,
      additionalParams: additionalParams,
    );

    if (result != null && result.wasAutoSwitched) {
      Log.i(
        '[MultiModelRouter] 👁️ AUTO-SWITCH for image analysis: ${result.originalProvider} → ${result.provider.providerId}',
      );
    }

    return result;
  }

  /// Special routing for realtime conversation
  static Future<RoutingResult?> routeRealtimeConversation({
    final String? preferredModel,
    final String? preferredProvider,
    final Map<String, dynamic>? additionalParams,
  }) async {
    Log.d('[MultiModelRouter] 🎙️ Routing realtime conversation request');

    final result = await route(
      capability: AICapability.realtimeConversation,
      preferredModel:
          preferredModel ?? 'gpt-4-realtime-preview', // Default realtime model
      preferredProvider: preferredProvider,
      additionalParams: additionalParams,
    );

    if (result != null && result.wasAutoSwitched) {
      Log.i(
        '[MultiModelRouter] 🎙️ AUTO-SWITCH for realtime: ${result.originalProvider} → ${result.provider.providerId}',
      );
    }

    return result;
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

  /// Get routing statistics
  static Map<String, dynamic> getRoutingStats() {
    final providers = _registry.getAllProviders();
    final stats = <String, dynamic>{
      'total_providers': providers.length,
      'healthy_providers': _registry.getHealthyProviders().length,
    };

    // Add capability coverage stats
    for (final capability in AICapability.values) {
      final supportingProviders = _registry.getProvidersForCapability(
        capability,
      );
      stats['${capability.name}_providers'] = supportingProviders.length;
      stats['${capability.name}_provider_ids'] = supportingProviders
          .map((final p) => p.providerId)
          .toList();
    }

    return stats;
  }

  /// Force refresh of provider registry
  static Future<void> refreshProviders() async {
    await _registry.refreshHealth();
    Log.i('[MultiModelRouter] Provider registry refreshed');
  }
}
