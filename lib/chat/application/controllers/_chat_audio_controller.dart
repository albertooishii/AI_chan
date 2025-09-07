import 'package:flutter/material.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/application/services/chat_application_service.dart';
import 'package:ai_chan/chat/application/mixins/ui_state_management_mixin.dart';
import 'package:ai_chan/chat/domain/interfaces/i_audio_chat_service.dart';

/// 🔊 **Chat Audio Controller** - DDD Specialized Controller
///
/// Handles all audio-related functionality for chat:
/// - Recording audio messages
/// - Playing audio messages
/// - TTS generation
/// - Audio state management
///
/// **DDD Principles:**
/// - Single Responsibility: Only audio operations
/// - Delegation: All logic delegated to ChatApplicationService
/// - UI State Management: Via mixin pattern
class ChatAudioController extends ChangeNotifier with UIStateManagementMixin {
  ChatAudioController({required final ChatApplicationService chatService})
    : _chatService = chatService;

  final ChatApplicationService _chatService;

  // Audio UI state getters (delegated to service)
  bool get isRecording => _chatService.isRecording;
  List<int> get currentWaveform => _chatService.currentWaveform;
  String get liveTranscript => _chatService.liveTranscript;
  Duration get recordingElapsed => _chatService.recordingElapsed;
  Duration get playingPosition => _chatService.playingPosition;
  Duration get playingDuration => _chatService.playingDuration;
  bool get isSendingAudio => _chatService.isSendingAudio;
  bool get isUploadingUserAudio => _chatService.isUploadingUserAudio;

  // Direct access to audio service for UI components
  IAudioChatService get audioService => _chatService.audioService;

  /// Start recording audio message
  Future<void> startRecording() async {
    await delegate(
      serviceCall: () => _chatService.startRecording(),
      errorMessage: 'Error al iniciar grabación',
    );
  }

  /// Cancel current recording
  Future<void> cancelRecording() async {
    await delegate(
      serviceCall: () => _chatService.cancelRecording(),
      errorMessage: 'Error al cancelar grabación',
    );
  }

  /// Stop recording and send as message
  Future<void> stopAndSendRecording({final String? model}) async {
    await executeWithNotification(
      operation: () async {
        final path = await _chatService.stopAndSendRecording(model: model);
        if (path != null) {
          // Audio processed and message sent
        }
      },
      errorMessage: 'Error al procesar grabación',
    );
  }

  /// Toggle audio playback for a message
  Future<void> togglePlayAudio(final Message msg) async {
    await delegate(
      serviceCall: () => _chatService.togglePlayAudio(msg),
      errorMessage: 'Error al reproducir audio',
    );
  }

  /// Generate TTS audio for a message
  Future<void> generateTtsForMessage(
    final Message msg, {
    final String voice = 'nova',
  }) async {
    await delegate(
      serviceCall: () => _chatService.generateTtsForMessage(msg, voice: voice),
      errorMessage: 'Error al generar TTS',
    );
  }

  /// Check if a message is currently playing
  bool isPlaying(final Message msg) => _chatService.isPlaying(msg);

  @override
  void dispose() {
    // Audio service disposal is handled by ChatApplicationService
    super.dispose();
  }
}
