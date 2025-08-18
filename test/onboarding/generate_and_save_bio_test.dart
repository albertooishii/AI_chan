import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/providers/onboarding_provider.dart';
import 'package:ai_chan/services/ai_service.dart';
import 'onboarding/fakes/fake_ai_service.dart';
import 'onboarding/fakes/fake_appearance_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('generateAndSaveBiography uses IA and saves to prefs', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    AIService.testOverride = FakeAIServiceImpl();

    final provider = OnboardingProvider();

    // Simulate calling generateAndSaveBiography; use a minimal BuildContext via pumpWidget
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      // call generation
      provider.generateAndSaveBiography(
        context: context,
        userName: 'UserX',
        aiName: 'AiX',
        userBirthday: DateTime(1990, 1, 1),
        meetStory: 'Historia',
        userCountryCode: 'ES',
        aiCountryCode: 'JP',
      );
      return const SizedBox.shrink();
    })));

    // Wait a small duration for async ops
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('onboarding_data'), isNotNull);

    AIService.testOverride = null;
  });
}
