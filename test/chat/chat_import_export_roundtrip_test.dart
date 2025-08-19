import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/providers/chat_provider.dart';
import 'package:ai_chan/core/models.dart';
import '../test_setup.dart';

void main() async {
  await initializeTestEnvironment();

  test('export and import roundtrip preserves messages and profile', () async {
    final provider = ChatProvider();
    provider.onboardingData = AiChanProfile(
      userName: 'U',
      aiName: 'A',
      userBirthday: DateTime(1990),
      aiBirthday: DateTime(2020),
      biography: {'summary': 's'},
      appearance: {'style': 'x'},
      timeline: [],
    );

    provider.messages = [
      Message(text: 'hello', sender: MessageSender.user, dateTime: DateTime.now(), status: MessageStatus.read),
      Message(text: 'resp', sender: MessageSender.assistant, dateTime: DateTime.now(), status: MessageStatus.read),
      Message(text: 'image msg', sender: MessageSender.user, dateTime: DateTime.now(), isImage: true, image: AiImage(url: 'https://img.test/1.png', seed: 's')),
    ];

    final jsonStr = await provider.exportAllToJson();
    expect(jsonStr, isNotEmpty);

    final imported = await provider.importAllFromJsonAsync(jsonStr);
    expect(imported, isNotNull);
    expect(provider.messages.length, 3);
    expect(provider.onboardingData.userName, 'U');
  });
}
