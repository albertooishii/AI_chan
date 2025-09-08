/// Tests for the YAML Configuration System (Phase 4)
/// This test file validates the configuration loading, provider factory,
/// and manager functionality.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_provider_config.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_config_loader.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_factory.dart';

void main() {
  group('AI Provider YAML Configuration System Tests', () {
    group('Configuration Loading Tests', () {
      test('should parse valid YAML configuration', () {
        const yamlConfig = '''
version: "1.0.0"
metadata:
  description: "Test configuration"
  created: "2025-09-08"
  last_updated: "2025-09-08"

global_settings:
  default_timeout_seconds: 30
  max_retries: 3
  retry_delay_seconds: 1
  enable_fallback: true
  log_provider_usage: true
  debug_mode: false

ai_providers:
  openai:
    enabled: true
    priority: 1
    display_name: "OpenAI GPT"
    description: "OpenAI models"
    capabilities:
      - text_generation
      - image_generation
    api_settings:
      base_url: "https://api.openai.com"
      version: "v1"
      authentication_type: "bearer_token"
      required_env_keys:
        - "OPENAI_API_KEY"
    models:
      text_generation:
        - "gpt-4.1"
        - "gpt-4o"
      image_generation:
        - "gpt-4.1"
    defaults:
      text_generation: "gpt-4.1"
      image_generation: "gpt-4.1"
    rate_limits:
      requests_per_minute: 3500
      tokens_per_minute: 350000
    configuration:
      max_context_tokens: 128000
      max_output_tokens: 4096
      supports_streaming: true
      supports_function_calling: true
      supports_tools: true

fallback_chains:
  text_generation:
    primary: "openai"
    fallbacks: []
  image_generation:
    primary: "openai"
    fallbacks: []
''';

        final config = AIProviderConfigLoader.loadFromString(yamlConfig);

        expect(config.version, '1.0.0');
        expect(config.metadata.description, 'Test configuration');
        expect(config.globalSettings.defaultTimeoutSeconds, 30);
        expect(config.aiProviders.length, 1);
        expect(config.aiProviders['openai']?.enabled, true);
        expect(config.aiProviders['openai']?.priority, 1);
        expect(
          config.aiProviders['openai']?.capabilities,
          contains(AICapability.textGeneration),
        );
        expect(config.fallbackChains.length, 2);
        expect(
          config.fallbackChains[AICapability.textGeneration]?.primary,
          'openai',
        );
      });

      test('should validate configuration structure', () {
        const invalidYaml = '''
version: "1.0.0"
# Missing required fields
metadata: {}
''';

        expect(
          () => AIProviderConfigLoader.loadFromString(invalidYaml),
          throwsA(isA<ConfigurationLoadException>()),
        );
      });

      test('should validate provider references in fallback chains', () {
        const invalidChainYaml = '''
version: "1.0.0"
metadata:
  description: "Test"
  created: "2025-09-08"
  last_updated: "2025-09-08"

global_settings:
  default_timeout_seconds: 30
  max_retries: 3
  retry_delay_seconds: 1
  enable_fallback: true
  log_provider_usage: true
  debug_mode: false

ai_providers:
  openai:
    enabled: true
    priority: 1
    display_name: "OpenAI"
    description: "OpenAI models"
    capabilities: [text_generation]
    api_settings:
      base_url: "https://api.openai.com"
      version: "v1"
      authentication_type: "bearer_token"
      required_env_keys: ["OPENAI_API_KEY"]
    models:
      text_generation: ["gpt-4.1"]
    defaults:
      text_generation: "gpt-4.1"
    rate_limits:
      requests_per_minute: 3500
      tokens_per_minute: 350000
    configuration:
      max_context_tokens: 128000
      max_output_tokens: 4096
      supports_streaming: true
      supports_function_calling: true
      supports_tools: true

fallback_chains:
  text_generation:
    primary: "nonexistent_provider"  # This should fail validation
    fallbacks: ["openai"]
''';

        expect(
          () => AIProviderConfigLoader.loadFromString(invalidChainYaml),
          throwsA(isA<ConfigurationLoadException>()),
        );
      });
    });

    group('Provider Factory Tests', () {
      test('should create providers from configuration', () {
        final providerConfig = const ProviderConfig(
          enabled: true,
          priority: 1,
          displayName: 'OpenAI GPT',
          description: 'OpenAI models',
          capabilities: [AICapability.textGeneration],
          apiSettings: ApiSettings(
            baseUrl: 'https://api.openai.com',
            version: 'v1',
            authenticationType: 'bearer_token',
            requiredEnvKeys: ['OPENAI_API_KEY'],
          ),
          models: {
            AICapability.textGeneration: ['gpt-4.1'],
          },
          defaults: {AICapability.textGeneration: 'gpt-4.1'},
          rateLimits: RateLimits(
            requestsPerMinute: 3500,
            tokensPerMinute: 350000,
          ),
          configuration: ProviderConfiguration(
            maxContextTokens: 128000,
            maxOutputTokens: 4096,
            supportsStreaming: true,
            supportsFunctionCalling: true,
            supportsTools: true,
          ),
        );

        final provider = AIProviderFactory.createProvider(
          'openai',
          providerConfig,
        );

        expect(provider.providerId, 'openai');
        expect(provider.supportsCapability(AICapability.textGeneration), true);
      });

      test('should support all known provider types', () {
        final supportedTypes = AIProviderFactory.getAvailableProviderTypes();

        expect(supportedTypes, contains('openai'));
        expect(supportedTypes, contains('google'));
        expect(supportedTypes, contains('xai'));

        for (final type in supportedTypes) {
          expect(AIProviderFactory.isProviderTypeSupported(type), true);
        }
      });

      test('should throw exception for unsupported provider type', () {
        final providerConfig = const ProviderConfig(
          enabled: true,
          priority: 1,
          displayName: 'Unknown Provider',
          description: 'Unknown provider',
          capabilities: [AICapability.textGeneration],
          apiSettings: ApiSettings(
            baseUrl: 'https://example.com',
            version: 'v1',
            authenticationType: 'bearer_token',
            requiredEnvKeys: ['API_KEY'],
          ),
          models: {
            AICapability.textGeneration: ['model-1'],
          },
          defaults: {AICapability.textGeneration: 'model-1'},
          rateLimits: RateLimits(
            requestsPerMinute: 1000,
            tokensPerMinute: 100000,
          ),
          configuration: ProviderConfiguration(
            maxContextTokens: 32000,
            maxOutputTokens: 2048,
            supportsStreaming: false,
            supportsFunctionCalling: false,
            supportsTools: false,
          ),
        );

        expect(
          () => AIProviderFactory.createProvider(
            'unknown_provider',
            providerConfig,
          ),
          throwsA(isA<ProviderCreationException>()),
        );
      });
    });

    group('Environment Override Tests', () {
      test('should apply environment-specific overrides', () {
        const yamlConfig = '''
version: "1.0.0"
metadata:
  description: "Test configuration"
  created: "2025-09-08"
  last_updated: "2025-09-08"

global_settings:
  default_timeout_seconds: 30
  max_retries: 3
  retry_delay_seconds: 1
  enable_fallback: true
  log_provider_usage: false
  debug_mode: false

ai_providers:
  openai:
    enabled: true
    priority: 1
    display_name: "OpenAI GPT"
    description: "OpenAI models"
    capabilities: [text_generation]
    api_settings:
      base_url: "https://api.openai.com"
      version: "v1"
      authentication_type: "bearer_token"
      required_env_keys: ["OPENAI_API_KEY"]
    models:
      text_generation: ["gpt-4.1", "gpt-4.1-mini"]
    defaults:
      text_generation: "gpt-4.1"
    rate_limits:
      requests_per_minute: 3500
      tokens_per_minute: 350000
    configuration:
      max_context_tokens: 128000
      max_output_tokens: 4096
      supports_streaming: true
      supports_function_calling: true
      supports_tools: true

fallback_chains:
  text_generation:
    primary: "openai"
    fallbacks: []

environments:
  development:
    global_settings:
      debug_mode: true
      log_provider_usage: true
    ai_providers:
      openai:
        enabled: true
        priority: 1
        display_name: "OpenAI GPT (Dev)"
        description: "OpenAI models for development"
        capabilities: [text_generation]
        api_settings:
          base_url: "https://api.openai.com"
          version: "v1"
          authentication_type: "bearer_token"
          required_env_keys: ["OPENAI_API_KEY"]
        models:
          text_generation: ["gpt-4.1-mini"]
        defaults:
          text_generation: "gpt-4.1-mini"
        rate_limits:
          requests_per_minute: 3500
          tokens_per_minute: 350000
        configuration:
          max_context_tokens: 128000
          max_output_tokens: 4096
          supports_streaming: true
          supports_function_calling: true
          supports_tools: true
''';

        final baseConfig = AIProviderConfigLoader.loadFromString(yamlConfig);
        final devConfig = AIProviderConfigLoader.applyEnvironmentOverrides(
          baseConfig,
          'development',
        );

        // Global settings should be overridden
        expect(devConfig.globalSettings.debugMode, true);
        expect(devConfig.globalSettings.logProviderUsage, true);

        // Provider settings should be overridden
        expect(
          devConfig.aiProviders['openai']?.displayName,
          'OpenAI GPT (Dev)',
        );
        expect(
          devConfig.aiProviders['openai']?.defaults[AICapability
              .textGeneration],
          'gpt-4.1-mini',
        );
      });
    });

    group('Integration Tests', () {
      test('should load configuration and create manager', () async {
        const yamlConfig = '''
version: "1.0.0"
metadata:
  description: "Test configuration"
  created: "2025-09-08"
  last_updated: "2025-09-08"

global_settings:
  default_timeout_seconds: 30
  max_retries: 3
  retry_delay_seconds: 1
  enable_fallback: true
  log_provider_usage: true
  debug_mode: false

ai_providers:
  openai:
    enabled: true
    priority: 1
    display_name: "OpenAI GPT"
    description: "OpenAI models"
    capabilities: [text_generation]
    api_settings:
      base_url: "https://api.openai.com"
      version: "v1"
      authentication_type: "bearer_token"
      required_env_keys: ["OPENAI_API_KEY"]
    models:
      text_generation: ["gpt-4.1"]
    defaults:
      text_generation: "gpt-4.1"
    rate_limits:
      requests_per_minute: 3500
      tokens_per_minute: 350000
    configuration:
      max_context_tokens: 128000
      max_output_tokens: 4096
      supports_streaming: true
      supports_function_calling: true
      supports_tools: true

fallback_chains:
  text_generation:
    primary: "openai"
    fallbacks: []
''';

        // Note: This test validates structure but won't fully initialize
        // providers without proper API keys in environment
        final config = AIProviderConfigLoader.loadFromString(yamlConfig);

        expect(config.aiProviders.length, 1);
        expect(config.fallbackChains.length, 1);

        // Validate factory can create providers
        final providers = AIProviderFactory.createProviders(config.aiProviders);
        expect(providers.length, 1);
        expect(providers.containsKey('openai'), true);
      });
    });
  });
}
