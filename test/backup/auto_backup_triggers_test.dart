import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/chat/application/providers/chat_provider.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/services/memory_summary_service.dart';
import 'package:ai_chan/shared/utils/backup_auto_uploader.dart';
import 'package:ai_chan/shared/services/google_backup_service.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';
import '../test_setup.dart';
import 'package:ai_chan/shared/services/ai_service.dart';

class _FakeGoogleSvc extends GoogleBackupService {
  final void Function()? onUpload;
  _FakeGoogleSvc({this.onUpload}) : super(accessToken: null);
  @override
  Future<String> uploadBackup(File zipFile, {String? filename}) async {
    onUpload?.call();
    return 'fake-id';
  }
}

class _FakeAiService implements AIService {
  @override
  Future<AIResponse> sendMessageImpl(
    List<Map<String, String>> history,
    SystemPrompt systemPrompt, {
    String? model,
    String? imageBase64,
    String? imageMimeType,
    bool enableImageGeneration = false,
  }) async {
    // Return a minimal valid JSON block that MemorySummaryService expects
    final json =
        '{"fecha_inicio":"2020-01-01","fecha_fin":"2020-01-02","eventos":[],"emociones":[],"resumen":"resumen de prueba","detalles_unicos":[]}';
    return AIResponse(text: json, base64: '', seed: '', prompt: '');
  }

  @override
  Future<List<String>> getAvailableModels() async => [];
}

Future<File> _fakeLocalBackupCreator({
  required String jsonStr,
  String? destinationDirPath,
}) async {
  // Create a tiny temp file to simulate the zip
  final dir = Directory(destinationDirPath ?? Directory.systemTemp.path);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final f = File(
    '${dir.path}/fake_backup_${DateTime.now().millisecondsSinceEpoch}.zip',
  );
  await f.writeAsBytes([0, 1, 2]);
  return f;
}

void main() async {
  await initializeTestEnvironment();

  setUp(() async {
    // Reset any test hooks and clear prefs to avoid coalescing blocking uploads
    BackupAutoUploader.resetForTests();
    // Ensure no previous last auto backup is recorded
    await PrefsUtils.removeKey(PrefsUtils.kLastAutoBackupMs);
    // Install fake AIService to avoid external network calls during summary generation
    AIService.testOverride = _FakeAiService();
  });

  tearDown(() async {
    AIService.testOverride = null;
  });

  test(
    'loadAll triggers auto-backup when there are messages but no recent backup (daily policy)',
    () async {
      final provider = ChatProvider();
      provider.googleLinked = true;
      provider.onboardingData = AiChanProfile(
        userName: 'T',
        aiName: 'AI',
        userBirthday: DateTime(1990),
        aiBirthday: DateTime(2020),
        biography: {},
        appearance: {},
        timeline: [],
      );

      var called = false;
      BackupAutoUploader.testLocalBackupCreator = _fakeLocalBackupCreator;
      BackupAutoUploader.testGoogleBackupServiceFactory = () =>
          _FakeGoogleSvc(onUpload: () => called = true);

      // Populate messages to simulate non-empty chat
      provider.messages = [
        Message(
          text: 'hi',
          sender: MessageSender.user,
          dateTime: DateTime.now(),
          status: MessageStatus.read,
        ),
      ];

      // Persist Google linked in prefs so loadAll fallback branch keeps googleLinked=true
      await PrefsUtils.setGoogleAccountInfo(
        email: 'a@b',
        avatar: null,
        name: 'a',
        linked: true,
      );
      // Call loadAll (fallback branch) which SHOULD trigger under the daily policy
      await provider.loadAll();

      // Allow a short delay for any async fire-and-forget calls
      await Future.delayed(const Duration(milliseconds: 400));
      // Under the new policy the loadAll will schedule an upload when there is
      // no recorded last auto-backup timestamp even if the chat contains
      // messages.
      expect(called, isTrue);
    },
  );

  test(
    'loadAll triggers auto-backup when messages empty and no previous backup',
    () async {
      final provider = ChatProvider();
      provider.googleLinked = true;
      provider.onboardingData = AiChanProfile(
        userName: 'T',
        aiName: 'AI',
        userBirthday: DateTime(1990),
        aiBirthday: DateTime(2020),
        biography: {},
        appearance: {},
        timeline: [],
      );

      BackupAutoUploader.testLocalBackupCreator = _fakeLocalBackupCreator;
      BackupAutoUploader.testGoogleBackupServiceFactory = () =>
          _FakeGoogleSvc(onUpload: () {});
      // Use a dedicated test completer on the uploader to observe the upload
      // attempt deterministically regardless of the fake service internals.
      final uploaderCompleter = Completer<void>();
      BackupAutoUploader.testUploadCompleter = uploaderCompleter;

      // Ensure messages empty and prefs has no last auto backup
      provider.messages = [];
      await PrefsUtils.removeKey(PrefsUtils.kLastAutoBackupMs);

      await PrefsUtils.setGoogleAccountInfo(
        email: 'a@b',
        avatar: null,
        name: 'a',
        linked: true,
      );
      await provider.loadAll();

      // Wait for the uploader completer (uploader invoked) or timeout
      await expectLater(uploaderCompleter.future, completes);
    },
  );

  test('triggers auto-backup on various chat actions when googleLinked', () async {
    final provider = ChatProvider();
    provider.googleLinked = true;
    provider.onboardingData = AiChanProfile(
      userName: 'T',
      aiName: 'AI',
      userBirthday: DateTime(1990),
      aiBirthday: DateTime(2020),
      biography: {},
      appearance: {},
      timeline: [],
    );

    final calls = <String>[];
    BackupAutoUploader.testLocalBackupCreator = _fakeLocalBackupCreator;
    BackupAutoUploader.testGoogleBackupServiceFactory = () =>
        _FakeGoogleSvc(onUpload: () => calls.add('upload'));

    // Start with empty messages so actions can occur
    provider.messages = [];
    await PrefsUtils.setGoogleAccountInfo(
      email: 'a@b',
      avatar: null,
      name: 'a',
      linked: true,
    );

    // 1) addAssistantMessage
    await provider.addAssistantMessage('assistant text');
    await Future.delayed(const Duration(milliseconds: 400));

    // 2) updateOrAddCallStatusMessage
    await provider.updateOrAddCallStatusMessage(
      text: 'call ended',
      callStatus: CallStatus.completed,
      incoming: false,
    );
    await Future.delayed(const Duration(milliseconds: 400));

    // 3) replaceIncomingCallPlaceholder (simulate placeholder exist)
    provider.messages.add(
      Message(
        text: '[call][/call]',
        sender: MessageSender.assistant,
        dateTime: DateTime.now(),
        status: MessageStatus.read,
      ),
    );
    provider.replaceIncomingCallPlaceholder(
      index: provider.messages.length - 1,
      summary: VoiceCallSummary(
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        duration: Duration(seconds: 10),
        messages: [],
        userSpoke: false,
        aiResponded: false,
      ),
      summaryText: 'call summary',
    );
    await Future.delayed(const Duration(milliseconds: 200));

    // 4) rejectIncomingCallPlaceholder
    provider.messages.add(
      Message(
        text: '[call][/call]',
        sender: MessageSender.assistant,
        dateTime: DateTime.now(),
        status: MessageStatus.read,
      ),
    );
    provider.rejectIncomingCallPlaceholder(
      index: provider.messages.length - 1,
      text: 'rejected',
    );
    await Future.delayed(const Duration(milliseconds: 200));

    // Expect at least one upload occurred for these actions (coalescing may dedupe)
    // Under the new policy, these actions do not create SUMMARY_BLOCK_SIZE blocks,
    // so no automatic backups should be triggered here.
    expect(calls.length, equals(0));
  });

  test(
    'generates summary block after SUMMARY_BLOCK_SIZE+1 messages and triggers backup',
    () async {
      final provider = ChatProvider();
      provider.googleLinked = true;
      provider.onboardingData = AiChanProfile(
        userName: 'T',
        aiName: 'AI',
        userBirthday: DateTime(1990),
        aiBirthday: DateTime(2020),
        biography: {},
        appearance: {},
        timeline: [],
      );

      BackupAutoUploader.testLocalBackupCreator = _fakeLocalBackupCreator;
      BackupAutoUploader.testGoogleBackupServiceFactory = () =>
          _FakeGoogleSvc(onUpload: () {});
      final uploaderCompleter = Completer<void>();
      BackupAutoUploader.testUploadCompleter = uploaderCompleter;

      provider.messages = [];
      await PrefsUtils.setGoogleAccountInfo(
        email: 'a@b',
        avatar: null,
        name: 'a',
        linked: true,
      );

      final blockSize = MemorySummaryService.maxHistory ?? 32;
      // Insert blockSize + 1 user messages to force at least one summary block creation
      final now = DateTime.now();
      for (int i = 0; i < blockSize + 1; i++) {
        provider.messages.add(
          Message(
            text: 'msg $i',
            sender: MessageSender.user,
            dateTime: now.add(Duration(seconds: i)),
            status: MessageStatus.read,
          ),
        );
      }

      // Simulate assistant response which triggers memory processing and backup trigger
      await provider.addAssistantMessage('assistant text to finalize');

      // Wait for the uploader completer to be completed when the upload starts
      await expectLater(uploaderCompleter.future, completes);
    },
  );
}
