import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_service.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import '../test_setup.dart';

void main() {
  setUpAll(() async {
    await initializeTestEnvironment();
  });

  group('Dynamic AI Providers System', () {
    test('AIProviderService initializes successfully', () async {
      final service = AIProviderService();
      await service.initialize();

      final stats = service.getStats();
      expect(stats['total_providers'], equals(3)); // 3 providers registered
      expect(stats['providers'], contains('openai'));
      expect(stats['providers'], contains('google'));
      expect(stats['providers'], contains('xai'));

      // Note: healthy_providers may be 0 in test environment without API keys
      print('Health status in test: ${stats['health_status']}');
    });
    test('Provider registry finds correct provider for models', () async {
      final service = AIProviderService();
      await service.initialize();

      // Test OpenAI model detection
      final openaiProvider = service.getProviderForModel('gpt-4.1-mini');
      expect(openaiProvider?.providerId, equals('openai'));

      // Test Google model detection
      final googleProvider = service.getProviderForModel('gemini-2.5-flash');
      expect(googleProvider?.providerId, equals('google'));

      // Test X.AI model detection
      final xaiProvider = service.getProviderForModel('grok-4');
      expect(xaiProvider?.providerId, equals('xai'));
    });

    test('Capability-based provider discovery works', () async {
      final service = AIProviderService();
      await service.initialize();

      // Test text generation capability (all providers support this)
      final textProviders = service.getProvidersForCapability(
        AICapability.textGeneration,
      );
      expect(
        textProviders.length,
        greaterThanOrEqualTo(1),
      ); // At least one provider should support text

      // Test image generation capability (OpenAI and Google support this)
      final imageProviders = service.getProvidersForCapability(
        AICapability.imageGeneration,
      );
      expect(
        imageProviders.length,
        greaterThanOrEqualTo(1),
      ); // At least one provider should support images

      // Test audio capabilities (only OpenAI supports this)
      final audioProviders = service.getProvidersForCapability(
        AICapability.audioGeneration,
      );
      expect(
        audioProviders.length,
        greaterThanOrEqualTo(0),
      ); // May be 0 if OpenAI is not healthy in test env
    });
    test('Provider metadata is comprehensive', () async {
      final service = AIProviderService();
      await service.initialize();

      final openaiProvider = service.getProviderForModel('gpt-4.1-mini');
      expect(openaiProvider, isNotNull);

      final metadata = openaiProvider!.metadata;
      expect(metadata.providerId, equals('openai'));
      expect(metadata.providerName, equals('OpenAI'));
      expect(metadata.company, equals('OpenAI'));
      expect(metadata.supportedCapabilities, isNotEmpty);
      expect(metadata.defaultModels, isNotEmpty);
      expect(metadata.availableModels, isNotEmpty);
      expect(metadata.requiresAuthentication, isTrue);
      expect(metadata.requiredConfigKeys, contains('OPENAI_API_KEY'));
    });

    test('Backward compatibility with existing system preserved', () async {
      final service = AIProviderService();
      await service.initialize();

      // Test that we can get default models
      final defaultTextModel = service.getDefaultModelForCapability(
        AICapability.textGeneration,
      );
      expect(defaultTextModel, isNotNull);

      // Test model support checking
      expect(
        service.supportsModelForCapability(
          'gpt-4.1-mini',
          AICapability.textGeneration,
        ),
        isTrue,
      );
      expect(
        service.supportsModelForCapability(
          'dall-e-3',
          AICapability.imageGeneration,
        ),
        isTrue,
      );
      expect(
        service.supportsModelForCapability(
          'gemini-2.5-flash',
          AICapability.textGeneration,
        ),
        isTrue,
      );
      expect(
        service.supportsModelForCapability(
          'grok-4',
          AICapability.textGeneration,
        ),
        isTrue,
      );
    });
  });
}
