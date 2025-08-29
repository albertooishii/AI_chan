import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/chat/application/utils/profile_persist_utils.dart';
import '../test_helpers.dart';
import 'package:ai_chan/core/models.dart';
import '../test_utils/prefs_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('profile_persist_utils', () {
    setUp(() {
      PrefsTestUtils.setMockInitialValues();
    });

    test('setOnboardingDataAndPersist updates profile and persists', () async {
      final provider = createTestChatProvider();
      final profile = AiChanProfile(
        userName: 'User',
        aiName: 'Ai',
        userBirthday: DateTime(1990, 1, 1),
        aiBirthday: null,
        biography: <String, dynamic>{'summary': 'bio'},
        appearance: <String, dynamic>{},
        timeline: <TimelineEntry>[],
      );

      await setOnboardingDataAndPersist(provider, profile);

      expect(provider.onboardingData.userName, equals('User'));
      expect(provider.onboardingData.aiName, equals('Ai'));
    });

    test('setEventsAndPersist updates events only', () async {
      final provider = createTestChatProvider();
      final events = [EventEntry(type: 'evento', description: 'E1', date: DateTime.now())];

      await setEventsAndPersist(provider, events);

      expect(provider.onboardingData.events, isNotNull);
      expect(provider.onboardingData.events!.length, equals(1));
      expect(provider.onboardingData.events!.first.description, equals('E1'));
    });
  });
}
