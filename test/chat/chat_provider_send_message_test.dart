import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/providers/chat_provider.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/interfaces/i_chat_repository.dart';
import 'package:ai_chan/core/interfaces/i_chat_response_service.dart';
import '../test_setup.dart';
import 'package:ai_chan/services/ai_service.dart';

// Local minimal fake for this test
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
    // Return a simple text response used by ChatProvider tests
    return AIResponse(
      text: 'respuesta de prueba',
      base64: '',
      seed: '',
      prompt: '',
    );
  }

  @override
  Future<List<String>> getAvailableModels() async => ['fake-model'];
}

class FakeRepo implements IChatRepository {
  Map<String, dynamic>? saved;

  @override
  Future<void> clearAll() async {}

  @override
  Future<Map<String, dynamic>?> loadAll() async => null;

  @override
  Future<String> exportAllToJson(Map<String, dynamic> map) async => '';

  @override
  Future<void> saveAll(Map<String, dynamic> map) async {
    saved = map;
  }

  @override
  Future<Map<String, dynamic>?> importAllFromJson(String jsonStr) async => null;
}

class FakeChatResponseService implements IChatResponseService {
  @override
  Future<Map<String, dynamic>> sendChat(
    List<Map<String, dynamic>> messages, {
    Map<String, dynamic>? options,
  }) async {
    return {
      'text': 'respuesta de prueba',
      'isImage': false,
      'finalModelUsed': options?['model'] ?? 'gemini-2.5-flash',
    };
  }

  @override
  Future<List<String>> getSupportedModels() async => ['gemini-2.5-flash'];
}

void main() {
  late FakeRepo fakeRepo;
  late ChatProvider provider;

  setUp(() async {
    await initializeTestEnvironment(
      dotenvContents:
          'DEFAULT_TEXT_MODEL=gpt-5-mini\nDEFAULT_IMAGE_MODEL=gpt-4.1-mini\nOPENAI_API_KEY=fake',
    );
    // Use fake AI service to avoid real network calls during summary generation
    AIService.testOverride = FakeAIServiceImpl();
    fakeRepo = FakeRepo();
    provider = ChatProvider(
      repository: fakeRepo,
      chatResponseService: FakeChatResponseService(),
    );
    // Initialize minimal profile
    provider.onboardingData = AiChanProfile(
      userName: 'User',
      aiName: 'Ai',
      userBirthday: DateTime(1990),
      aiBirthday: DateTime(2020),
      biography: {'summary': 'x'},
      appearance: {'style': 'x'},
      timeline: [],
    );
    // Add SUMMARY_BLOCK_SIZE + 1 fake messages for summary/testing
    final now = DateTime.now();
    final count = Config.getSummaryBlockSize() + 1;
    final fakeMessages = List.generate(count, (i) {
      return Message(
        text: 'mensaje falso ${i + 1}',
        sender: MessageSender.user,
        dateTime: now.subtract(Duration(minutes: count - i)),
        status: MessageStatus.read,
      );
    });
    provider.messages.addAll(fakeMessages);
  });

  tearDown(() {
    AIService.testOverride = null;
  });

  test('sendMessage adds user message and receives ai response', () async {
    await provider.sendMessage('hola mundo');
    // Last message should be assistant
    expect(provider.messages.isNotEmpty, true);
    expect(provider.messages.last.sender, MessageSender.assistant);
    expect(provider.messages.last.text, contains('respuesta'));
  });
}
