import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/shared/ai_providers/core/interfaces/i_ai_provider.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/shared/ai_providers/implementations/openai_provider.dart';
import 'package:ai_chan/shared/ai_providers/implementations/google_provider.dart';
import 'package:ai_chan/shared/ai_providers/implementations/xai_provider.dart';

/// 🧪 Test tan chulo como el de voice_integration_test pero para los models
/// Verifica que los providers exponen modelos correctamente via metadata
void main() {
  group('🤖 Model Integration Tests - Provider Model Discovery', () {
    group('📝 Text Generation Models - Metadata Discovery', () {
      test(
        'OpenAI provider should expose text generation models in metadata',
        () {
          final openaiProvider = OpenAIProvider();

          expect(
            openaiProvider.metadata,
            isNotNull,
            reason: 'OpenAI should have metadata',
          );
          expect(
            openaiProvider.supportsCapability(AICapability.textGeneration),
            isTrue,
            reason: 'OpenAI should support text generation',
          );

          final models = openaiProvider.metadata.getAvailableModels(
            AICapability.textGeneration,
          );
          expect(
            models,
            isNotNull,
            reason: 'OpenAI should return text generation models',
          );
          expect(
            models,
            isA<List<String>>(),
            reason: 'Should return List<String>',
          );
          expect(models, isNotEmpty, reason: 'Should have predefined models');

          print(
            '✅ OpenAI expuso ${models.length} modelos de texto desde metadata',
          );
          print('📋 Modelos: ${models.join(', ')}');

          // Check for known OpenAI models
          final hasKnownModels = models.any(
            (model) => [
              'gpt-4',
              'gpt-5',
              'gpt-4.1',
            ].any((known) => model.contains(known)),
          );
          expect(
            hasKnownModels,
            isTrue,
            reason: 'Should contain known OpenAI models',
          );
        },
      );

      test(
        'Google provider should expose text generation models in metadata',
        () {
          final googleProvider = GoogleProvider();

          expect(
            googleProvider.metadata,
            isNotNull,
            reason: 'Google should have metadata',
          );
          expect(
            googleProvider.supportsCapability(AICapability.textGeneration),
            isTrue,
            reason: 'Google should support text generation',
          );

          final models = googleProvider.metadata.getAvailableModels(
            AICapability.textGeneration,
          );
          expect(
            models,
            isNotNull,
            reason: 'Google should return text generation models',
          );
          expect(
            models,
            isA<List<String>>(),
            reason: 'Should return List<String>',
          );
          expect(models, isNotEmpty, reason: 'Should have predefined models');

          print(
            '✅ Google expuso ${models.length} modelos de texto desde metadata',
          );
          print('📋 Modelos: ${models.join(', ')}');

          // Check for known Google models
          final hasKnownModels = models.any(
            (model) =>
                ['gemini', 'bison'].any((known) => model.contains(known)),
          );
          expect(
            hasKnownModels,
            isTrue,
            reason: 'Should contain known Google models',
          );
        },
      );

      test('XAI provider should expose text generation models in metadata', () {
        final xaiProvider = XAIProvider();

        expect(
          xaiProvider.metadata,
          isNotNull,
          reason: 'XAI should have metadata',
        );
        expect(
          xaiProvider.supportsCapability(AICapability.textGeneration),
          isTrue,
          reason: 'XAI should support text generation',
        );

        final models = xaiProvider.metadata.getAvailableModels(
          AICapability.textGeneration,
        );
        expect(
          models,
          isNotNull,
          reason: 'XAI should return text generation models',
        );
        expect(
          models,
          isA<List<String>>(),
          reason: 'Should return List<String>',
        );
        expect(models, isNotEmpty, reason: 'Should have predefined models');

        print('✅ XAI expuso ${models.length} modelos de texto desde metadata');
        print('📋 Modelos: ${models.join(', ')}');

        // Check for known XAI models
        final hasKnownModels = models.any((model) => model.contains('grok'));
        expect(
          hasKnownModels,
          isTrue,
          reason: 'Should contain known XAI models',
        );
      });
    });

    group('🎨 Image Generation Models - Metadata Discovery', () {
      test(
        'OpenAI provider should expose image generation models in metadata',
        () {
          final openaiProvider = OpenAIProvider();

          expect(
            openaiProvider.supportsCapability(AICapability.imageGeneration),
            isTrue,
            reason: 'OpenAI should support image generation',
          );

          final models = openaiProvider.metadata.getAvailableModels(
            AICapability.imageGeneration,
          );
          expect(
            models,
            isNotNull,
            reason: 'OpenAI should return image generation models',
          );
          expect(
            models,
            isA<List<String>>(),
            reason: 'Should return List<String>',
          );
          expect(models, isNotEmpty, reason: 'Should have predefined models');

          print(
            '✅ OpenAI expuso ${models.length} modelos de imagen desde metadata',
          );
          print('📋 Modelos: ${models.join(', ')}');
        },
      );

      test(
        'Google provider should expose image generation models in metadata',
        () {
          final googleProvider = GoogleProvider();

          if (googleProvider.supportsCapability(AICapability.imageGeneration)) {
            final models = googleProvider.metadata.getAvailableModels(
              AICapability.imageGeneration,
            );
            expect(
              models,
              isNotNull,
              reason: 'Google should return image generation models',
            );
            print(
              '✅ Google expuso ${models.length} modelos de imagen desde metadata',
            );
          } else {
            print('ℹ️ Google no soporta image generation según metadata');
          }
        },
      );
    });

    group('🎤 Realtime/Voice Models - Direct Access', () {
      test('OpenAI provider should expose realtime models directly', () {
        final openaiProvider = OpenAIProvider();

        expect(
          openaiProvider.supportsRealtime,
          isTrue,
          reason: 'OpenAI should support realtime',
        );

        final models = openaiProvider.getAvailableRealtimeModels();
        expect(
          models,
          isNotNull,
          reason: 'OpenAI should return realtime models',
        );
        expect(
          models,
          isA<List<String>>(),
          reason: 'Should return List<String>',
        );
        expect(models, isNotEmpty, reason: 'Should have predefined models');

        print('✅ OpenAI expuso ${models.length} modelos realtime');
        print('📋 Modelos: ${models.join(', ')}');

        // Check for GPT-4o realtime models
        final hasRealtimeModels = models.any(
          (model) => model.contains('realtime'),
        );
        expect(
          hasRealtimeModels,
          isTrue,
          reason: 'Should contain realtime models',
        );
      });

      test('Provider realtime support validation', () {
        // Create providers using concrete types but work with interface
        final List<IAIProvider> providers = [
          OpenAIProvider(),
          GoogleProvider(),
          XAIProvider(),
        ];

        for (final IAIProvider provider in providers) {
          final supportsRealtime = provider.supportsRealtime;
          print(
            '📋 Provider ${provider.providerId} supports realtime: $supportsRealtime',
          );

          if (supportsRealtime) {
            final realtimeModels = provider.getAvailableRealtimeModels();
            expect(
              realtimeModels,
              isNotNull,
              reason:
                  'Provider with realtime support should return realtime models',
            );
            print(
              '✅ ${provider.providerId} tiene ${realtimeModels.length} modelos realtime',
            );
          }
        }
      });
    });

    group('🔧 Provider Capability Discovery', () {
      test('All providers should support text generation', () {
        final List<IAIProvider> providers = [
          OpenAIProvider(),
          GoogleProvider(),
          XAIProvider(),
        ];

        for (final IAIProvider provider in providers) {
          final supportsText = provider.supportsCapability(
            AICapability.textGeneration,
          );
          expect(
            supportsText,
            isTrue,
            reason: '${provider.providerId} should support text generation',
          );

          print(
            '✅ Provider ${provider.providerId} soporta generación de texto',
          );

          // Check capabilities
          final capabilities = provider.supportedCapabilities;
          expect(
            capabilities,
            isNotEmpty,
            reason: '${provider.providerId} should have capabilities',
          );
          expect(
            capabilities,
            contains(AICapability.textGeneration),
            reason: '${provider.providerId} should support text generation',
          );

          print(
            '📋 ${provider.providerId} capabilities: ${capabilities.map((c) => c.displayName).join(', ')}',
          );
        }
      });

      test('Provider metadata should be valid', () {
        final List<IAIProvider> providers = [
          OpenAIProvider(),
          GoogleProvider(),
          XAIProvider(),
        ];

        for (final IAIProvider provider in providers) {
          // Verify provider has valid metadata
          expect(
            provider,
            isA<IAIProvider>(),
            reason: '${provider.runtimeType} should implement IAIProvider',
          );

          // Check that provider ID is set
          expect(
            provider.providerId,
            isNotEmpty,
            reason: '${provider.runtimeType} should have a provider ID',
          );

          // Check provider name
          expect(
            provider.providerName,
            isNotEmpty,
            reason: '${provider.runtimeType} should have a provider name',
          );

          // Check version
          expect(
            provider.version,
            isNotEmpty,
            reason: '${provider.runtimeType} should have a version',
          );

          // Check metadata
          expect(
            provider.metadata,
            isNotNull,
            reason: '${provider.runtimeType} should have metadata',
          );

          print(
            '✅ Provider ${provider.providerId} metadata válida: ${provider.providerName} v${provider.version}',
          );
        }
      });

      test('Provider default models should be accessible', () {
        final openaiProvider = OpenAIProvider();
        final capabilities = [
          AICapability.textGeneration,
          AICapability.imageGeneration,
          AICapability.imageAnalysis,
          AICapability.audioGeneration,
          AICapability.audioTranscription,
        ];

        for (final capability in capabilities) {
          if (openaiProvider.supportsCapability(capability)) {
            final defaultModel = openaiProvider.getDefaultModel(capability);
            expect(
              defaultModel,
              isNotNull,
              reason: 'Should have default model for ${capability.displayName}',
            );
            expect(
              defaultModel,
              isNotEmpty,
              reason:
                  'Default model should not be empty for ${capability.displayName}',
            );

            print(
              '✅ OpenAI ${capability.displayName} default model: $defaultModel',
            );
          } else {
            print('ℹ️ OpenAI no soporta ${capability.displayName}');
          }
        }
      });
    });

    group('🏗️ Architecture Compliance', () {
      test('Provider interface consistency', () {
        final List<IAIProvider> providers = [
          OpenAIProvider(),
          GoogleProvider(),
          XAIProvider(),
        ];

        for (final IAIProvider provider in providers) {
          // All providers should implement IAIProvider
          expect(provider, isA<IAIProvider>());

          // All providers should have basic properties
          expect(provider.providerId, isNotEmpty);
          expect(provider.providerName, isNotEmpty);
          expect(provider.version, isNotEmpty);
          expect(provider.metadata, isNotNull);
          expect(provider.supportedCapabilities, isNotEmpty);
          expect(provider.availableModels, isNotEmpty);

          // All providers should support at least text generation
          expect(
            provider.supportsCapability(AICapability.textGeneration),
            isTrue,
          );

          print('✅ ${provider.providerId} cumple con IAIProvider interface');
        }
      });

      test('Model discovery methods exist', () {
        final List<IAIProvider> providers = [
          OpenAIProvider(),
          GoogleProvider(),
          XAIProvider(),
        ];

        for (final IAIProvider provider in providers) {
          // Check that required methods exist (won't call them to avoid API issues)
          expect(
            provider.getDefaultModel(AICapability.textGeneration),
            isNotNull,
          );
          expect(
            provider.supportsModel(AICapability.textGeneration, 'test-model'),
            isA<bool>(),
          );
          expect(provider.getRateLimits(), isA<Map<String, int>>());

          print('✅ ${provider.providerId} tiene todos los métodos requeridos');
        }
      });
    });
  });
}
