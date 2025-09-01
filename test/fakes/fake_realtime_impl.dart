import 'dart:async';

import 'package:ai_chan/core/interfaces/i_realtime_client.dart';

class FakeRealtimeIClient implements IRealtimeClient {
  bool connected = false;
  final List<List<int>> appended = [];
  bool commitCalled = false;
  final List<String> sentTexts = [];

  @override
  bool get isConnected => connected;

  @override
  void appendAudio(List<int> bytes) {
    appended.add(List<int>.from(bytes));
  }

  @override
  Future<void> commitPendingAudio() async {
    commitCalled = true;
  }

  @override
  Future<void> connect({
    required String systemPrompt,
    String voice = '',
    String? inputAudioFormat,
    String? outputAudioFormat,
    String? turnDetectionType,
    int? silenceDurationMs,
    Map<String, dynamic>? options,
  }) async {
    connected = true;
  }

  @override
  void requestResponse({bool audio = true, bool text = true}) {}

  @override
  void sendText(String text) {
    sentTexts.add(text);
  }

  @override
  void updateVoice(String voice) {}

  @override
  Future<void> close() async {
    connected = false;
  }

  // Implementaciones por defecto de los nuevos métodos
  @override
  void sendImageWithText({
    required String imageBase64,
    String? text,
    String imageFormat = 'png',
  }) {
    // Fake implementation - could track calls if needed
  }

  @override
  void configureTools(List<Map<String, dynamic>> tools) {
    // Fake implementation - could track calls if needed
  }

  @override
  void sendFunctionCallOutput({
    required String callId,
    required String output,
  }) {
    // Fake implementation - could track calls if needed
  }

  @override
  void cancelResponse({String? itemId, int? sampleCount}) {
    // Fake implementation - could track calls if needed
  }
}
