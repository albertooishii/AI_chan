import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/shared/infrastructure/utils/backup_utils.dart';
import 'package:ai_chan/shared/infrastructure/utils/chat_json_utils.dart'
    as chat_json_utils;
import 'package:ai_chan/shared/domain/models/index.dart';

void main() {
  test('BackupUtils export and parse roundtrip', () async {
    final profile = AiChanProfile(
      userName: 'TestUser',
      aiName: 'TestAI',
      userBirthdate: DateTime(1990),
      aiBirthdate: DateTime(2020),
      biography: {},
      appearance: {},
    );

    final msg = Message(
      text: 'hello',
      sender: MessageSender.user,
      dateTime: DateTime.now(),
      status: MessageStatus.read,
    );

    final imported = ChatExport(
      profile: profile,
      messages: [msg],
      events: [],
      timeline: [],
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
