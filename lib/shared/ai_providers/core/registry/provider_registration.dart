/// Central registration point for all AI Providers.
/// This file replaces hardcoded imports and switch statements.
library;

import 'package:ai_chan/shared/ai_providers/core/registry/provider_auto_registry.dart';
import 'package:ai_chan/shared/ai_providers/implementations/google_provider.dart';
import 'package:ai_chan/shared/ai_providers/implementations/openai_provider.dart';
import 'package:ai_chan/shared/ai_providers/implementations/xai_provider.dart';
import 'package:ai_chan/shared.dart'; // Consolidated import

/// Register all available AI Providers with the auto-registry system.
/// This is the ONLY place where providers need to be explicitly listed.
///
/// To add a new provider:
/// 1. Import the provider class
/// 2. Add a registerConstructor call
/// 3. That's it! No other code changes needed.
void registerAllProviders() {
  Log.i('[ProviderRegistration] Registering all AI providers...');

  try {
    // Register OpenAI Provider
    ProviderAutoRegistry.registerConstructor(
      'openai',
      (final ProviderConfig config) => OpenAIProvider(),
      modelPrefixes: ['gpt-', 'dall-e', 'gpt-realtime'],
    );

    // Register Google Provider
    ProviderAutoRegistry.registerConstructor(
      'google',
      (final ProviderConfig config) => GoogleProvider(),
      modelPrefixes: ['gemini-', 'imagen-'],
    );

    // Register XAI Provider
    ProviderAutoRegistry.registerConstructor(
      'xai',
      (final ProviderConfig config) => XAIProvider(),
      modelPrefixes: ['grok-'],
    );

    // 🚀 ADDING NEW PROVIDERS:
    // Simply add more registerConstructor calls here:
    //
    // ProviderAutoRegistry.registerConstructor(
    //   'claude',
    //   (ProviderConfig config) => ClaudeProvider(),
    //   modelPrefixes: ['claude-', 'claude2-', 'claude3-'],
    // );
    //
    // ProviderAutoRegistry.registerConstructor(
    //   'mistral',
    //   (ProviderConfig config) => MistralProvider(),
    //   modelPrefixes: ['mistral-', 'mixtral-'],
    // );

    final stats = ProviderAutoRegistry.getStats();
    Log.i(
      '[ProviderRegistration] ✅ Registration complete: ${stats['registered_providers']} providers',
    );
    Log.d('[ProviderRegistration] Registered providers: ${stats['providers']}');
  } on Exception catch (e) {
    Log.e('[ProviderRegistration] ❌ Failed to register providers: $e');
    rethrow;
  }
}

/// Check if a specific provider is registered
bool isProviderRegistered(final String providerId) {
  return ProviderAutoRegistry.isProviderRegistered(providerId);
}

/// Get provider ID for a specific model
String? getProviderIdForModel(final String modelId) {
  return ProviderAutoRegistry.getProviderForModel(modelId);
}

/// Get model prefixes for a provider
List<String>? getModelPrefixesForProvider(final String providerId) {
  return ProviderAutoRegistry.getModelPrefixes(providerId);
}

/// Initialize the provider registration system
void initializeProviderSystem() {
  Log.i('[ProviderRegistration] Initializing provider system...');

  // Register all providers
  registerAllProviders();

  // Initialize auto-registry
  ProviderAutoRegistry.initializeKnownProviders();

  Log.i('[ProviderRegistration] ✅ Provider system initialized');
}
