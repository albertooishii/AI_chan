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
  void appendAudio(final List<int> bytes) {
    appended.add(List<int>.from(bytes));
  }

  @override
  Future<void> commitPendingAudio() async {
    commitCalled = true;
  }

  @override
  Future<void> connect({
    required final String systemPrompt,
    final String voice = '',
    final String? inputAudioFormat,
    final String? outputAudioFormat,
    final String? turnDetectionType,
    final int? silenceDurationMs,
    final Map<String, dynamic>? options,
  }) async {
    connected = true;
  }

  @override
  void requestResponse({final bool audio = true, final bool text = true}) {}

  @override
  void sendText(final String text) {
    sentTexts.add(text);
  }

  @override
  void updateVoice(final String voice) {}

  @override
  Future<void> close() async {
    connected = false;
  }

  // Implementaciones por defecto de los nuevos métodos
  @override
  void sendImageWithText({
    required final String imageBase64,
    final String? text,
    final String imageFormat = 'png',
  }) {
    // Fake implementation - could track calls if needed
  }

  @override
  void configureTools(final List<Map<String, dynamic>> tools) {
    // Fake implementation - could track calls if needed
  }

  @override
  void sendFunctionCallOutput({
    required final String callId,
    required final String output,
  }) {
    // Fake implementation - could track calls if needed
  }

  @override
  void cancelResponse({final String? itemId, final int? sampleCount}) {
    // Fake implementation - could track calls if needed
  }
}
