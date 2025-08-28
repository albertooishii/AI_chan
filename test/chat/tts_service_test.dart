import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/chat/application/services/tts_service.dart';
import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';

class FakeAudioService implements IAudioChatService {
  final File? toReturn;
  FakeAudioService(this.toReturn);

  @override
  bool get isRecording => false;

  @override
  List<int> get currentWaveform => [];

  @override
  String get liveTranscript => '';

  @override
  Duration get recordingElapsed => Duration.zero;

  @override
  Duration get currentPosition => Duration.zero;

  @override
  Duration get currentDuration => Duration.zero;

  @override
  Future<void> startRecording() async {}

  @override
  Future<void> cancelRecording() async {}

  @override
  Future<String?> stopRecording({bool cancelled = false}) async => null;

  @override
  Future<void> togglePlay(message, onState) async {}

  @override
  Future<File?> synthesizeTts(
    String text, {
    String voice = 'sage',
    String? languageCode,
    bool forDialogDemo = false,
  }) async {
    return toReturn;
  }

  @override
  bool isPlayingMessage(message) => false;

  @override
  void dispose() {}
}

void main() {
  test('TtsService synthesizes and persists file when audioService returns file', () async {
    final baseTmp = Directory('${Directory.systemTemp.path}/ai_chan');
    if (!baseTmp.existsSync()) baseTmp.createSync(recursive: true);
    final tmp = File('${baseTmp.path}/tts_test_${DateTime.now().millisecondsSinceEpoch}.wav');
    await tmp.writeAsString('fake');
    final fake = FakeAudioService(tmp);
    final svc = TtsService(fake, localAudioDirGetter: () async => baseTmp);
    final path = await svc.synthesizeAndPersist('hola mundo', voice: 'nova');
    expect(path, isNotNull);
    // Cleanup
    try {
      final f = File(path!);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  });

  test('TtsService returns null when audioService returns null', () async {
    final fake = FakeAudioService(null);
    final baseTmp2 = Directory('${Directory.systemTemp.path}/ai_chan');
    if (!baseTmp2.existsSync()) baseTmp2.createSync(recursive: true);
    final svc = TtsService(fake, localAudioDirGetter: () async => baseTmp2);
    final path = await svc.synthesizeAndPersist('hola mundo', voice: 'nova');
    expect(path, isNull);
  });
}
