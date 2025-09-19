import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';
import 'package:ai_chan/shared/domain/models/index.dart';

/// Basic implementation of IAudioChatService for dependency injection
/// TODO: Implement actual audio chat functionality
class BasicAudioChatService implements IAudioChatService {
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
  bool isPlayingMessage(final Message message) => false;

  @override
  Future<void> startRecording() async {
    // TODO: Implement recording
    throw UnimplementedError('Audio recording not yet implemented');
  }

  @override
  Future<String?> stopRecording({final bool cancelled = false}) async {
    // TODO: Implement stop recording
    return null;
  }

  @override
  Future<void> cancelRecording() async {
    // TODO: Implement cancel recording
  }

  @override
  Future<void> togglePlay(
    final Message message,
    final OnStateChanged onState,
  ) async {
    // TODO: Implement audio playback
  }

  @override
  Future<String?> synthesizeTts(
    final String text, {
    final String? languageCode,
    final bool forDialogDemo = false,
  }) async {
    // TODO: Implement TTS synthesis
    return null;
  }

  @override
  void dispose() {
    // TODO: Clean up resources
  }
}
