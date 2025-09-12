import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:ai_chan/shared/ai_providers/core/models/ai_provider_config.dart';
import '../test_setup.dart';

/// Helper function to convert YamlMap to Map&lt;String, dynamic&gt; recursively
dynamic yamlToMap(dynamic yaml) {
  if (yaml is YamlMap) {
    return Map<String, dynamic>.from(
      yaml.map((key, value) => MapEntry(key.toString(), yamlToMap(value))),
    );
  } else if (yaml is YamlList) {
    return yaml.map((item) => yamlToMap(item)).toList();
  } else {
    return yaml;
  }
}

/// 🧪 Simple Tests for AI Providers Configuration YAML
/// Focuses on key validation to ensure the YAML issue is resolved
void main() {
  group('AI Providers Configuration Tests', () {
    late String yamlContent;
    late dynamic parsedYaml;

    setUpAll(() async {
      // Initialize test environment first
      await initializeTestEnvironment();

      // Load YAML content once for all tests
      final file = File('assets/ai_providers_config.yaml');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'AI providers config file should exist',
      );
      yamlContent = await file.readAsString();
      parsedYaml = loadYaml(yamlContent);
    });

    test('should parse YAML without errors', () {
      expect(() => loadYaml(yamlContent), returnsNormally);
      expect(parsedYaml, isNotNull);
    });

    test('should have ai_providers section', () {
      expect(parsedYaml.containsKey('ai_providers'), isTrue);
      expect(parsedYaml['ai_providers'], isNotNull);
    });

    test('should have all expected providers', () {
      final providers =
          yamlToMap(parsedYaml['ai_providers']) as Map<String, dynamic>;

      // Check that we have the key providers
      expect(
        providers.containsKey('openai'),
        isTrue,
        reason: 'OpenAI provider should exist',
      );
      expect(
        providers.containsKey('google'),
        isTrue,
        reason: 'Google provider should exist',
      );
      expect(
        providers.containsKey('xai'),
        isTrue,
        reason: 'XAI provider should exist',
      );
    });

    test('should create ProviderConfig objects without errors', () {
      final providers =
          yamlToMap(parsedYaml['ai_providers']) as Map<String, dynamic>;

      for (final providerEntry in providers.entries) {
        final providerName = providerEntry.key;
        final providerData =
            yamlToMap(providerEntry.value) as Map<String, dynamic>;

        expect(
          () => ProviderConfig.fromMap(providerData),
          returnsNormally,
          reason: 'Should create ProviderConfig for $providerName',
        );
      }
    });

    test('should have android_native_tts section', () {
      expect(parsedYaml.containsKey('android_native_tts'), isTrue);
      expect(parsedYaml['android_native_tts'], isNotNull);
    });

    test('XAI provider should be at root level (not nested)', () {
      final providers =
          yamlToMap(parsedYaml['ai_providers']) as Map<String, dynamic>;

      // This test specifically validates the fix for the original YAML issue
      expect(
        providers.containsKey('xai'),
        isTrue,
        reason: 'XAI should be at the root level of ai_providers',
      );

      // Also check that android_native_tts doesn't contain providers
      final androidTts =
          yamlToMap(parsedYaml['android_native_tts']) as Map<String, dynamic>;
      expect(
        androidTts.containsKey('xai'),
        isFalse,
        reason: 'XAI should NOT be nested under android_native_tts',
      );
    });

    test('should have required sections', () {
      final requiredSections = [
        'version',
        'metadata',
        'ai_providers',
        'android_native_tts',
        'fallback_chains',
        'routing_rules',
      ];

      for (final section in requiredSections) {
        expect(
          parsedYaml.containsKey(section),
          isTrue,
          reason: 'Missing required section: $section',
        );
      }
    });
  });
}
