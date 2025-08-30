import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/shared/utils/backup_utils.dart';
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
import 'package:ai_chan/core/models.dart';

void main() {
  test('BackupUtils export and parse roundtrip', () async {
    final profile = AiChanProfile(
      userName: 'TestUser',
      aiName: 'TestAI',
      userBirthday: DateTime(1990, 1, 1),
      aiBirthday: DateTime(2020, 1, 1),
      timeline: [],
      biography: {},
      appearance: {},
    );

    final msg = Message(
      text: 'hello',
      sender: MessageSender.user,
      dateTime: DateTime.now(),
      isImage: false,
      status: MessageStatus.read,
    );

    final imported = ImportedChat(
      profile: profile,
      messages: [msg],
      events: [],
    );

    final jsonStr = await BackupUtils.exportImportedChatToJson(imported);
    expect(jsonStr, isNotNull);
    expect(jsonStr, isNotEmpty);

    final parsed = await chat_json_utils.ChatJsonUtils.importAllFromJson(
      jsonStr,
    );
    expect(parsed, isNotNull);
    expect(parsed!.profile.userName, equals('TestUser'));
    expect(parsed.messages.length, equals(1));
    expect(parsed.messages.first.text, equals('hello'));
  });
}
