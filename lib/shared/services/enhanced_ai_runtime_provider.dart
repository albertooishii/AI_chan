import 'dart:async';

import '../ai_providers/core/models/ai_capability.dart';
import '../ai_providers/core/interfaces/i_ai_provider.dart';
import '../../core/models/ai_response.dart';
import '../../core/models/system_prompt.dart';
import '../ai_providers/core/services/ai_provider_manager.dart';
import '../utils/log_utils.dart';
import '../services/ai_service.dart' as runtime_ai;

/// Enhanced AI Runtime Provider that bridges new provider system with legacy runtime
/// This replaces the original ai_runtime_provider.dart with improved architecture
class EnhancedAIRuntimeProvider {
  static AIProviderManager? _providerManager;

  /// Initialize the enhanced provider system
  static Future<void> initialize() async {
    try {
      _providerManager = AIProviderManager.instance;
      await _providerManager!.initialize();
      Log.i('Enhanced AI Runtime Provider initialized successfully');
    } on Exception catch (e) {
      Log.e('Failed to initialize Enhanced AI Runtime Provider', error: e);
      // Continue with legacy fallback
    }
  }

  /// Main factory method that replaces the original getAIServiceForModel
  /// Uses new provider system first, falls back to legacy if needed
  static Future<runtime_ai.AIService> getAIServiceForModel(
    final String modelId,
  ) async {
    try {
      // Try new provider system first
      if (_providerManager != null) {
        final capability = _determineCapabilityFromModel(modelId);
        final provider = await _providerManager!.getProviderForCapability(
          capability,
        );

        if (provider != null) {
          Log.i('Using new provider system for model: $modelId');
          return AIProviderBridge(provider);
        }
      }

      Log.w(
        'New provider system unavailable, falling back to legacy for model: $modelId',
      );
      return _createLegacyService(modelId);
    } on Exception catch (e) {
      Log.e('Error in getAIServiceForModel', error: e);
      return _createLegacyService(modelId);
    }
  }

  /// Determine AI capability based on model ID
  static AICapability _determineCapabilityFromModel(final String modelId) {
    final modelLower = modelId.toLowerCase();

    if (modelLower.contains('gpt') || modelLower.contains('openai')) {
      return AICapability.textGeneration;
    } else if (modelLower.contains('gemini') || modelLower.contains('google')) {
      return AICapability
          .textGeneration; // ✅ CORREGIDO: Gemini también es principalmente generación de texto
    } else if (modelLower.contains('grok') || modelLower.contains('xai')) {
      return AICapability.textGeneration;
    }

    // Default to text generation
    return AICapability.textGeneration;
  }

  /// Create mock service when Enhanced AI is not available
  static runtime_ai.AIService _createLegacyService(final String modelId) {
    Log.w('Enhanced AI not available, creating mock service for: $modelId');
    return _MockService(modelId);
  }
}

/// Bridge class that wraps new IAIProvider to work with legacy AIService interface
class AIProviderBridge implements runtime_ai.AIService {
  AIProviderBridge(this._provider);
  final IAIProvider _provider;

  @override
  Future<AIResponse> sendMessageImpl(
    final List<Map<String, String>> history,
    final SystemPrompt systemPrompt, {
    final String? model,
    final String? imageBase64,
    final String? imageMimeType,
    final bool enableImageGeneration = false,
  }) async {
    try {
      // Call new provider with appropriate capability
      final capability = enableImageGeneration
          ? AICapability.imageGeneration
          : (imageBase64 != null
                ? AICapability.imageAnalysis
                : AICapability.textGeneration);

      final response = await _provider.sendMessage(
        history: history,
        systemPrompt: systemPrompt,
        capability: capability,
        model: model,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
      );

      // Return response as-is since both use AIResponse from core/models
      return response;
    } on Exception catch (e) {
      Log.e('Error in AIProviderBridge.sendMessageImpl', error: e);
      return AIResponse(text: 'Failed to process message: ${e.toString()}');
    }
  }

  @override
  Future<List<String>> getAvailableModels() async {
    try {
      // Get models for all supported capabilities
      final allModels = <String>[];

      for (final capability in _provider.supportedCapabilities) {
        final models = await _provider.getAvailableModelsForCapability(
          capability,
        );
        allModels.addAll(models);
      }

      // Remove duplicates and return
      return allModels.toSet().toList();
    } on Exception catch (e) {
      Log.e('Error in AIProviderBridge.getAvailableModels', error: e);
      return [];
    }
  }
}

/// Mock service for fallback scenarios
class _MockService implements runtime_ai.AIService {
  _MockService(this.providerName);
  final String providerName;

  @override
  Future<AIResponse> sendMessageImpl(
    final List<Map<String, String>> history,
    final SystemPrompt systemPrompt, {
    final String? model,
    final String? imageBase64,
    final String? imageMimeType,
    final bool enableImageGeneration = false,
  }) async {
    Log.w('Using mock service for provider: $providerName');

    return AIResponse(
      text: 'Mock response from $providerName provider. Service unavailable.',
    );
  }

  @override
  Future<List<String>> getAvailableModels() async {
    return ['mock-model-$providerName'];
  }
}
