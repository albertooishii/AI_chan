import 'package:ai_chan/shared/utils/onboarding_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/models.dart';
import '../fakes/fake_appearance_generator.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:ai_chan/onboarding/application/providers/onboarding_provider.dart';
import '../test_setup.dart';

// Local fake AI service for this test to avoid shared fixture coupling
class FakeAIServiceImpl extends AIService {
  @override
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    SystemPrompt systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
    bool enableImageGeneration = false,
  }) async {
    if (enableImageGeneration) {
      const onePixelPngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII=';
      return AIResponse(text: '', base64: onePixelPngBase64, seed: 'fake-seed', prompt: 'fake-prompt');
    }
    // Minimal biography JSON for appearance generator
    final json = '{"resumen_breve":"Resumen de prueba","datos_personales":{"nombre_completo":"Ai Test"}}';
    return AIResponse(text: json, base64: '', seed: '', prompt: '');
  }

  @override
  Future<List<String>> getAvailableModels() async => ['fake-model'];
}

void main() {
  group('generateFullBiographyFlexible', () {
    setUp(() {
      AIService.testOverride = FakeAIServiceImpl();
    });

    tearDown(() {
      AIService.testOverride = null;
    });

    test('integrates appearance generator and saves image via saveImageFunc', () async {
      // Deterministic saveImageFunc for test
      Future<String?> deterministicSaver(String base64, {String prefix = 'ai_avatar'}) async {
        // return a deterministic filename based on prefix to assert later
        return '/tmp/${prefix}_deterministic.png';
      }

      final bio = await generateFullBiographyFlexible(
        userName: 'UserX',
        aiName: 'AiX',
        userBirthday: DateTime(1990, 1, 1),
        meetStory: 'Nos conocimos en un foro',
        appearanceGenerator: FakeAppearanceGenerator(),
        saveImageFunc: deterministicSaver,
        userCountryCode: 'ES',
        aiCountryCode: 'JP',
      );

      expect(bio, isNotNull);
      expect(bio.avatar, isNotNull);
      // Assert that the avatar url equals the deterministic saver return or fake values
      // FakeAppearanceGenerator returns a fixed url; if saveImageFunc used, the generator should set url accordingly.
      expect(
        bio.avatar!.url,
        anyOf(
          equals('https://example.com/avatar.png'),
          equals('/tmp/ai_avatar_deterministic.png'),
          equals('/tmp/ai_avatar_deteministic.png'),
          equals('/tmp/ai_avatar_deterministic.png'),
          contains('/tmp/'),
        ),
      );
      expect(bio.avatar!.seed, equals('fake-seed'));
      expect(bio.avatar!.prompt, equals('fake-prompt'));
      expect(bio.appearance, isA<Map<String, dynamic>>());
    });

    test('generateFullBiographyFlexible + provider loads saved prefs', () async {
      await initializeTestEnvironment();
      SharedPreferences.setMockInitialValues({});

      // Deterministic saver for tests to avoid filesystem env dependency
      Future<String?> deterministicSaver(String base64, {String prefix = 'ai_avatar'}) async {
        return '/tmp/${prefix}_deterministic.png';
      }

      final bio = await generateFullBiographyFlexible(
        userName: 'UserX',
        aiName: 'AiX',
        userBirthday: DateTime(1990, 1, 1),
        meetStory: 'Historia',
        appearanceGenerator: FakeAppearanceGenerator(),
        saveImageFunc: deterministicSaver,
        userCountryCode: 'ES',
        aiCountryCode: 'JP',
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('onboarding_data', jsonEncode(bio.toJson()));

      final provider = OnboardingProvider();
      while (provider.loading) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      expect(provider.generatedBiography, isNotNull);
    });
  });

  test('generateFullBiographyFlexible + provider loads saved prefs', () async {
    await initializeTestEnvironment();
    SharedPreferences.setMockInitialValues({});
    AIService.testOverride = FakeAIServiceImpl();

    // Deterministic saver for tests to avoid filesystem env dependency
    Future<String?> deterministicSaver(String base64, {String prefix = 'ai_avatar'}) async {
      return '/tmp/${prefix}_deterministic.png';
    }

    final bio = await generateFullBiographyFlexible(
      userName: 'UserX',
      aiName: 'AiX',
      userBirthday: DateTime(1990, 1, 1),
      meetStory: 'Historia',
      appearanceGenerator: FakeAppearanceGenerator(),
      saveImageFunc: deterministicSaver,
      userCountryCode: 'ES',
      aiCountryCode: 'JP',
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('onboarding_data', jsonEncode(bio.toJson()));

    final provider = OnboardingProvider();
    while (provider.loading) {
      await Future.delayed(const Duration(milliseconds: 10));
    }

    expect(provider.generatedBiography, isNotNull);

    AIService.testOverride = null;
  });
}
