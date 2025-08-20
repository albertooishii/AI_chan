import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/onboarding/application/providers/onboarding_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_setup.dart';

void main() {
  test('OnboardingProvider loads profile from SharedPreferences', () async {
    await initializeTestEnvironment();

    final profile = AiChanProfile(
      biography: {'resumen_breve': 'Perfil desde prefs.'},
      userName: 'UserPref',
      aiName: 'AIPref',
      userBirthday: DateTime(1992, 2, 2),
      aiBirthday: DateTime(2002, 3, 3),
      appearance: {},
      timeline: [],
    );

    SharedPreferences.setMockInitialValues({
      'onboarding_data': jsonEncode(profile.toJson()),
    });

    final provider = OnboardingProvider();

    final completer = Completer<void>();
    provider.addListener(() {
      if (!provider.loading && !completer.isCompleted) completer.complete();
    });

    // Wait until provider finishes loading (timeout to avoid hanging)
    await completer.future.timeout(const Duration(seconds: 5));

    expect(provider.generatedBiography, isNotNull);
    expect(provider.biographySaved, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('onboarding_data'), isNotNull);
  });
}
