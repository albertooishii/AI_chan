import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/shared/services/backup_service.dart';
import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:ai_chan/shared/utils/backup_utils.dart' show BackupUtils;
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
import 'package:ai_chan/core/models.dart';
import '../test_setup.dart';
import 'package:ai_chan/shared/utils/image_utils.dart' as image_utils;
import 'package:ai_chan/shared/utils/audio_utils.dart' as audio_utils;

void main() async {
  await initializeTestEnvironment();

  test('full backup save and restore roundtrip (media + json)', () async {
    // Prepare provider with profile and messages
    final provider = ChatProvider();
    provider.onboardingData = AiChanProfile(
      userName: 'TestUser',
      aiName: 'TestAI',
      userBirthday: DateTime(1990),
      aiBirthday: DateTime(2020),
      biography: {'summary': 's'},
      appearance: {'style': 'x'},
      timeline: [],
    );

    provider.messages = [
      Message(text: 'hello', sender: MessageSender.user, dateTime: DateTime.now(), status: MessageStatus.read),
      Message(
        text: 'assistant reply',
        sender: MessageSender.assistant,
        dateTime: DateTime.now(),
        status: MessageStatus.read,
      ),
    ];

    // Create dummy media files in the test override directories
    final imgDir = await image_utils.getLocalImageDir();
    final audioDir = await audio_utils.getLocalAudioDir();

    final imgFile = File('${imgDir.path}/test_image.png');
    await imgFile.writeAsBytes(List<int>.generate(10, (i) => i));
    final audioFile = File('${audioDir.path}/test_audio.wav');
    await audioFile.writeAsBytes(List<int>.generate(20, (i) => i + 1));

    // Sanity: files exist
    expect(await imgFile.exists(), isTrue);
    expect(await audioFile.exists(), isTrue);

    // Create a temp destination directory to simulate user-chosen path
    final baseTmp = Directory('${Directory.systemTemp.path}/ai_chan');
    if (!baseTmp.existsSync()) baseTmp.createSync(recursive: true);
    final destDir = Directory('${baseTmp.path}/backup_dest_${DateTime.now().millisecondsSinceEpoch}')
      ..createSync(recursive: true);

    // Create the backup and assert file created in destDir
    final jsonStr = await BackupUtils.exportChatPartsToJson(
      profile: provider.onboardingData,
      messages: provider.messages,
      events: provider.events,
    );
    final backupFile = await BackupService.createLocalBackup(jsonStr: jsonStr, destinationDirPath: destDir.path);
    expect(await backupFile.exists(), isTrue);

    // Clear provider state and delete media to simulate fresh device
    await provider.clearAll();
    expect(provider.messages, isEmpty);

    // Remove media files
    if (await imgFile.exists()) await imgFile.delete();
    if (await audioFile.exists()) await audioFile.delete();

    expect((await image_utils.getLocalImageDir()).listSync(), isEmpty);
    expect((await audio_utils.getLocalAudioDir()).listSync(), isEmpty);

    // Restore from backup
    final extractedJson = await BackupService.restoreAndExtractJson(backupFile);
    final imported = await chat_json_utils.ChatJsonUtils.importAllFromJson(extractedJson);
    expect(imported, isNotNull);
    if (imported != null) {
      provider.onboardingData = imported.profile;
      provider.messages = imported.messages.cast<Message>();
      await provider.saveAll();
    }

    // Validate provider state restored
    expect(provider.onboardingData.userName, equals('TestUser'));
    expect(provider.messages.length, equals(2));

    // Validate media restored into the test dirs
    final restoredImg = File('${imgDir.path}/test_image.png');
    final restoredAudio = File('${audioDir.path}/test_audio.wav');
    expect(await restoredImg.exists(), isTrue);
    expect(await restoredAudio.exists(), isTrue);

    // Cleanup
    try {
      if (await restoredImg.exists()) await restoredImg.delete();
      if (await restoredAudio.exists()) await restoredAudio.delete();
      if (await backupFile.exists()) await backupFile.delete();
      await destDir.delete(recursive: true);
    } catch (_) {}
  });
}
