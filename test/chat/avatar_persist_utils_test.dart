import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/chat/application/utils/avatar_persist_utils.dart';
import '../test_helpers.dart';
import 'package:ai_chan/core/models.dart';
import '../test_utils/prefs_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('avatar_persist_utils', () {
    setUp(() {
      PrefsTestUtils.setMockInitialValues();
    });

    test('addAvatarAndPersist adds avatar and persists', () async {
      final provider = createTestChatProvider();
      final avatar = AiImage(url: 'http://example.com/img.png', seed: 's1');

      await addAvatarAndPersist(provider, avatar);

      expect(provider.onboardingData.avatars, isNotNull);
      expect(
        provider.onboardingData.avatars!.any((a) => a.seed == 's1'),
        isTrue,
      );
    });

    test(
      'removeImageFromProfileAndPersist removes avatar when present',
      () async {
        final provider = createTestChatProvider();
        final avatar1 = AiImage(url: 'http://example.com/img1.png', seed: 's1');
        final avatar2 = AiImage(url: 'http://example.com/img2.png', seed: 's2');
        // add both
        await addAvatarAndPersist(provider, avatar1);
        await addAvatarAndPersist(provider, avatar2);
        expect(provider.onboardingData.avatars!.length, equals(2));

        await removeImageFromProfileAndPersist(provider, avatar1);
        expect(
          provider.onboardingData.avatars!.any((a) => a.seed == 's1'),
          isFalse,
        );
        expect(
          provider.onboardingData.avatars!.any((a) => a.seed == 's2'),
          isTrue,
        );
      },
    );
  });
}
