import '../test_setup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:ai_chan/core/models.dart';
import '../core/services/fake_ai_service.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'dart:io';
import 'package:ai_chan/core/config.dart';

/// Helper provider that overrides the dialog to return a deterministic choice
class TestChatProvider extends ChatProvider {
  final String dialogResult;

  TestChatProvider({required this.dialogResult}) : super(repository: null, chatResponseService: null);

  @override
  Future<String?> showRegenerateAppearanceErrorDialog(Object error) async {
    // Avoid showing real UI during tests; return the configured choice.
    return dialogResult;
  }
}

void main() async {
  await initializeTestEnvironment();

  test('createAvatarFromAppearance appends avatar and system message on success', () async {
    final provider = TestChatProvider(dialogResult: 'cancel');
    provider.onboardingData = AiChanProfile(
      events: [],
      userName: 'u',
      aiName: 'ai',
      userBirthday: null,
      aiBirthday: null,
      biography: {},
      appearance: {'hair': 'brown'},
      timeline: [],
      avatars: [],
    );

    // Fake AI returns a valid base64 PNG (1x1) -- reuse existing test fixture used elsewhere
    const png1x1 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=';
    final fakeResp = AIResponse(text: '', base64: png1x1, seed: 'seed123', prompt: 'pp');
    final fake = FakeAIService([fakeResp]);
    AIService.testOverride = fake;
    final tmp = Directory.systemTemp.createTempSync('ai_chan_test_images_');
    Config.setOverrides({'IMAGE_DIR_DESKTOP': tmp.path});

    try {
      expect(provider.onboardingData.avatars?.length ?? 0, 0);
      expect(provider.messages.length, 0);

      await provider.createAvatarFromAppearance(replace: false);

      expect(provider.onboardingData.avatars?.length ?? 0, 1);
      // System message appended
      expect(provider.messages.any((m) => m.sender == MessageSender.system), true);
    } finally {
      AIService.testOverride = null;
      try {
        Config.setOverrides(null);
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test('createAvatarFromAppearance retries when first attempt fails and user chooses retry', () async {
    final provider = TestChatProvider(dialogResult: 'retry');
    provider.onboardingData = AiChanProfile(
      events: [],
      userName: 'u',
      aiName: 'ai',
      userBirthday: null,
      aiBirthday: null,
      biography: {},
      appearance: {'hair': 'black'},
      timeline: [],
      avatars: [],
    );

    // First fake: returns no base64 (will cause IAAvatarGenerator to fail)
    final failResp = AIResponse(text: '', base64: '', seed: '', prompt: '');
    // Second fake: valid image
    const png1x1 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=';
    final okResp = AIResponse(text: '', base64: png1x1, seed: 's2', prompt: 'pp');
    final fake = FakeAIService([failResp, okResp]);
    AIService.testOverride = fake;
    final tmp = Directory.systemTemp.createTempSync('ai_chan_test_images_');
    Config.setOverrides({'IMAGE_DIR_DESKTOP': tmp.path});

    try {
      expect(provider.onboardingData.avatars?.length ?? 0, 0);

      await provider.createAvatarFromAppearance(replace: false);

      // After retry, should have one avatar appended
      expect(provider.onboardingData.avatars?.length ?? 0, 1);
      expect(provider.messages.any((m) => m.sender == MessageSender.system), true);
    } finally {
      AIService.testOverride = null;
      try {
        Config.setOverrides(null);
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test('createAvatarFromAppearance with replace=true replaces avatar and does not add system message', () async {
    final provider = TestChatProvider(dialogResult: 'cancel');
    provider.onboardingData = AiChanProfile(
      events: [],
      userName: 'u',
      aiName: 'ai',
      userBirthday: null,
      aiBirthday: null,
      biography: {},
      appearance: {'hair': 'red'},
      timeline: [],
      avatars: [AiImage(url: 'old.png', seed: 'old', prompt: 'old')],
    );

    const png1x1 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=';
    final fakeResp = AIResponse(text: '', base64: png1x1, seed: 'newseed', prompt: 'pp');
    final fake = FakeAIService([fakeResp]);
    AIService.testOverride = fake;
    final tmp = Directory.systemTemp.createTempSync('ai_chan_test_images_');
    Config.setOverrides({'IMAGE_DIR_DESKTOP': tmp.path});

    try {
      expect(provider.onboardingData.avatars?.length ?? 0, 1);
      expect(provider.messages.where((m) => m.sender == MessageSender.system).length, 0);

      await provider.createAvatarFromAppearance(replace: true);

      // Should replace existing avatars with the new one
      expect(provider.onboardingData.avatars?.length ?? 0, 1);
      expect(provider.onboardingData.avatars?.first.seed, 'newseed');
      // No system message should be appended when replace=true
      expect(provider.messages.where((m) => m.sender == MessageSender.system).length, 0);
    } finally {
      AIService.testOverride = null;
      try {
        Config.setOverrides(null);
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    }
  });
}
