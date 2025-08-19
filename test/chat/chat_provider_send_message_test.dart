import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/providers/chat_provider.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/interfaces/i_chat_repository.dart';
import 'package:ai_chan/core/interfaces/i_chat_response_service.dart';
import '../test_setup.dart';

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
  Future<Map<String, dynamic>> sendChat(List<Map<String, dynamic>> messages, {Map<String, dynamic>? options}) async {
    return {'text': 'respuesta de prueba', 'isImage': false, 'finalModelUsed': options?['model'] ?? 'gemini-2.5-flash'};
  }

  @override
  Future<List<String>> getSupportedModels() async => ['gemini-2.5-flash'];
}

void main() {
  late FakeRepo fakeRepo;
  late ChatProvider provider;

  setUp(() async {
    await initializeTestEnvironment();
    fakeRepo = FakeRepo();
    provider = ChatProvider(repository: fakeRepo, chatResponseService: FakeChatResponseService());
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
  });

  test('sendMessage adds user message and receives ai response', () async {
    await provider.sendMessage('hola mundo');
    // Last message should be assistant
    expect(provider.messages.isNotEmpty, true);
    expect(provider.messages.last.sender, MessageSender.assistant);
    expect(provider.messages.last.text, contains('respuesta'));
  });
}
