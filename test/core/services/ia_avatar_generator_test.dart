import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/services/ia_avatar_generator.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import '../../fakes/fake_ai_service.dart';
import 'package:ai_chan/core/models.dart';
import 'dart:io';
import 'package:ai_chan/core/config.dart';

void main() {
  test(
    'generateAvatarWithRetries returns AiImage when AI provides base64',
    () async {
      // tiny 1x1 PNG base64 to allow saveBase64ImageToFile to succeed in tests
      final png1x1 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=';
      final fakeResp = AIResponse(
        text: '',
        base64: png1x1,
        seed: 'seed123',
        prompt: 'pp',
      );
      final fake = FakeAIService.withResponses([fakeResp]);
      AIService.testOverride = fake;
      // Provide writable test image dir so saveBase64ImageToFile can succeed
      final baseTmp = Directory('${Directory.systemTemp.path}/ai_chan');
      if (!baseTmp.existsSync()) baseTmp.createSync(recursive: true);
      final tmp = Directory(
        '${baseTmp.path}/images_${DateTime.now().millisecondsSinceEpoch}',
      )..createSync(recursive: true);
      Config.setOverrides({'TEST_IMAGE_DIR': tmp.path});

      final gen = IAAvatarGenerator();
      final profile = AiChanProfile(
        biography: <String, dynamic>{'text': 'hobbies'},
        userName: 'u',
        aiName: 'a',
        userBirthdate: null,
        aiBirthdate: null,
        appearance: <String, dynamic>{},
        timeline: [],
      );

      final img = await gen.generateAvatarFromAppearance(profile);
      expect(img, isNotNull);
      expect(img.seed, 'seed123');

      AIService.testOverride = null;
      try {
        Config.setOverrides(null);
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    },
  );

  test('generateAvatarWithRetries throws when no base64 returned', () async {
    final fake = FakeAIService.withResponses([
      AIResponse(text: ''),
      AIResponse(text: ''),
    ]);
    AIService.testOverride = fake;
    final baseTmp = Directory('${Directory.systemTemp.path}/ai_chan');
    if (!baseTmp.existsSync()) baseTmp.createSync(recursive: true);
    final tmp = Directory(
      '${baseTmp.path}/images_${DateTime.now().millisecondsSinceEpoch}',
    )..createSync(recursive: true);
    Config.setOverrides({'TEST_IMAGE_DIR': tmp.path});

    final gen = IAAvatarGenerator();
    final profile = AiChanProfile(
      biography: <String, dynamic>{'text': 'hobbies'},
      userName: 'u',
      aiName: 'a',
      userBirthdate: null,
      aiBirthdate: null,
      appearance: <String, dynamic>{},
      timeline: [],
    );

    try {
      await gen.generateAvatarFromAppearance(profile);
      fail('Expected exception');
    } catch (e) {
      expect(e, isA<Exception>());
    }

    AIService.testOverride = null;
    try {
      Config.setOverrides(null);
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });
}
