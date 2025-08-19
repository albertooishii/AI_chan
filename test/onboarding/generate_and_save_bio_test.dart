import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/providers/onboarding_provider.dart';
import 'package:ai_chan/services/ai_service.dart';
import 'fakes/fake_ai_service.dart';
import 'fakes/fake_appearance_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:ai_chan/utils/onboarding_utils.dart';

void main() {
  test('generateFullBiographyFlexible + provider loads saved prefs', () async {
    SharedPreferences.setMockInitialValues({});
    AIService.testOverride = FakeAIServiceImpl();

    // Generate a biography using the flexible generator and fake appearance generator
    final bio = await generateFullBiographyFlexible(
      userName: 'UserX',
      aiName: 'AiX',
      userBirthday: DateTime(1990, 1, 1),
      meetStory: 'Historia',
      appearanceGenerator: FakeAppearanceGenerator(),
      userCountryCode: 'ES',
      aiCountryCode: 'JP',
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('onboarding_data', jsonEncode(bio.toJson()));

    // Now create provider which should load from prefs
    final provider = OnboardingProvider();

    // wait until provider done loading
    while (provider.loading) {
      await Future.delayed(const Duration(milliseconds: 10));
    }

    expect(provider.generatedBiography, isNotNull);

    AIService.testOverride = null;
  });
}
