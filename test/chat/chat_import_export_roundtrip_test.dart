import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:ai_chan/shared/utils/backup_utils.dart' show BackupUtils;
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
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
      Message(
        text: 'image msg',
        sender: MessageSender.user,
        dateTime: DateTime.now(),
        isImage: true,
        image: AiImage(url: 'https://img.test/1.png', seed: 's'),
      ),
    ];

    final jsonStr = await BackupUtils.exportChatPartsToJson(
      profile: provider.onboardingData,
      messages: provider.messages,
      events: provider.events,
    );
    expect(jsonStr, isNotEmpty);

    final imported = await chat_json_utils.ChatJsonUtils.importAllFromJson(jsonStr);
    expect(imported, isNotNull);
    if (imported != null) {
      provider.onboardingData = imported.profile;
      provider.messages = imported.messages.cast<Message>();
      await provider.saveAll();
    }
    expect(provider.messages.length, 3);
    expect(provider.onboardingData.userName, 'U');
  });
}
