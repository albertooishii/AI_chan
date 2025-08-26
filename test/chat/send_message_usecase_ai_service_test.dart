import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/shared/services/ai_service.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/application/use_cases/send_message_use_case.dart';

class FakeAIService implements AIService {
  bool called = false;
  @override
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    SystemPrompt systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
    bool enableImageGeneration = false,
  }) async {
    called = true;
    return AIResponse(text: 'hola desde fake', base64: '', seed: '', prompt: '');
  }

  @override
  Future<List<String>> getAvailableModels() async => ['gpt-fake'];
}

void main() {
  test('SendMessageUseCase uses AIService when no injectedService provided', () async {
    final fake = FakeAIService();
    AIService.testOverride = fake;

    final useCase = SendMessageUseCase();

    final recent = <Message>[
      Message(text: 'hola', sender: MessageSender.user, dateTime: DateTime.now(), status: MessageStatus.sent),
    ];
    final profile = AiChanProfile(
      userName: 'u',
      aiName: 'ai',
      userBirthday: DateTime(2000, 1, 1),
      aiBirthday: DateTime(2000, 1, 1),
      biography: {},
      appearance: {},
      timeline: [],
      avatars: null,
    );
    final systemPrompt = SystemPrompt(profile: profile, dateTime: DateTime.now(), recentMessages: [], instructions: {});

    final outcome = await useCase.sendChat(recentMessages: recent, systemPromptObj: systemPrompt, model: 'gpt-fake');

    expect(fake.called, isTrue);
    expect(outcome.result.text, contains('hola desde fake'));

    AIService.testOverride = null;
  });
}
