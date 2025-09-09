import 'dart:async';
import 'package:ai_chan/core/models/image.dart';

typedef ScheduleSendFn =
    Future<void> Function(String text, {AiImage? image, String? imageMimeType});

/// Minimal controller that exposes actions and ValueListenables for the
/// MessageInput widget so the widget doesn't depend on Provider directly.
class ChatInputController {
  ChatInputController({
    required this.scheduleSend,
    this.startRecording,
    this.stopAndSendRecording,
    this.cancelRecording,
    this.onUserTyping,
  });
  final ScheduleSendFn scheduleSend;
  final Future<void> Function()? startRecording;
  final Future<void> Function()? stopAndSendRecording;
  final Future<void> Function()? cancelRecording;
  final void Function(String)? onUserTyping;

  // Simple notifiers using StreamController for lightweight demo purposes.
  final StreamController<bool> _isRecording = StreamController.broadcast();
  final StreamController<List<int>> _waveform = StreamController.broadcast();
  final StreamController<Duration> _elapsed = StreamController.broadcast();
  final StreamController<String> _liveTranscript = StreamController.broadcast();

  Stream<bool> get isRecordingStream => _isRecording.stream;
  Stream<List<int>> get waveformStream => _waveform.stream;
  Stream<Duration> get elapsedStream => _elapsed.stream;
  Stream<String> get liveTranscriptStream => _liveTranscript.stream;

  // Helpers for providers to push state into the streams
  void pushIsRecording(final bool v) => _isRecording.add(v);
  void pushWaveform(final List<int> v) => _waveform.add(v);
  void pushElapsed(final Duration d) => _elapsed.add(d);
  void pushLiveTranscript(final String s) => _liveTranscript.add(s);

  void dispose() {
    try {
      _isRecording.close();
    } on Exception catch (_) {}
    try {
      _waveform.close();
    } on Exception catch (_) {}
    try {
      _elapsed.close();
    } on Exception catch (_) {}
    try {
      _liveTranscript.close();
    } on Exception catch (_) {}
  }
}
