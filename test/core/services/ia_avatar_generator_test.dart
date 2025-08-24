import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/services/ia_avatar_generator.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'fake_ai_service.dart';
import 'package:ai_chan/core/models.dart';
import 'dart:io';
import 'package:ai_chan/core/config.dart';

void main() {
  test('generateAvatarWithRetries returns AiImage when AI provides base64', () async {
    // tiny 1x1 PNG base64 to allow saveBase64ImageToFile to succeed in tests
    final png1x1 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=';
    final fakeResp = AIResponse(text: '', base64: png1x1, seed: 'seed123', prompt: 'pp');
    final fake = FakeAIService([fakeResp]);
    AIService.testOverride = fake;
    // Provide writable IMAGE_DIR_DESKTOP so saveBase64ImageToFile can succeed
    final tmp = Directory.systemTemp.createTempSync('ai_chan_test_images_');
    Config.setOverrides({'IMAGE_DIR_DESKTOP': tmp.path});

    final gen = IAAvatarGenerator();
    final profile = AiChanProfile(
      biography: <String, dynamic>{'text': 'hobbies'},
      userName: 'u',
      aiName: 'a',
      userBirthday: null,
      aiBirthday: null,
      appearance: <String, dynamic>{},
      avatars: null,
      timeline: [],
    );

    final img = await gen.generateAvatarWithRetries(profile, maxAttempts: 2);
    expect(img, isNotNull);
    expect(img.seed, 'seed123');

    AIService.testOverride = null;
    try {
      Config.setOverrides(null);
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('generateAvatarWithRetries throws when no base64 returned', () async {
    final fake = FakeAIService([
      AIResponse(text: '', base64: '', seed: '', prompt: ''),
      AIResponse(text: '', base64: '', seed: '', prompt: ''),
    ]);
    AIService.testOverride = fake;
    final tmp = Directory.systemTemp.createTempSync('ai_chan_test_images_');
    Config.setOverrides({'IMAGE_DIR_DESKTOP': tmp.path});

    final gen = IAAvatarGenerator();
    final profile = AiChanProfile(
      biography: <String, dynamic>{'text': 'hobbies'},
      userName: 'u',
      aiName: 'a',
      userBirthday: null,
      aiBirthday: null,
      appearance: <String, dynamic>{},
      avatars: null,
      timeline: [],
    );

    try {
      await gen.generateAvatarWithRetries(profile, maxAttempts: 2);
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
